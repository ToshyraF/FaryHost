package handlers

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/ToshyraF/FaryHost/backend/internal/httpjson"
	"github.com/ToshyraF/FaryHost/backend/internal/middleware"
	"github.com/ToshyraF/FaryHost/backend/internal/models"
	"github.com/ToshyraF/FaryHost/backend/internal/omise"
)

type createOrderItemRequest struct {
	MenuItemID string `json:"menu_item_id"`
	Quantity   int    `json:"quantity"`
}

type createOrderRequest struct {
	VendorID string                   `json:"vendor_id"`
	Note     string                   `json:"note"`
	Items    []createOrderItemRequest `json:"items"`
}

// CreateOrder สั่งอาหารล่วงหน้า (pre-order) 1 ออเดอร์
// จะตรวจสอบรายการสินค้าทุกชิ้นกับเมนูจริงของร้านค้า ณ ตอนนี้ แล้ว "snapshot"
// ชื่อ/ราคาเก็บไว้ในออเดอร์ เพื่อไม่ให้การแก้เมนูภายหลังไปกระทบยอดเงินของ
// ออเดอร์เก่าที่สั่งไปแล้ว จากนั้นสร้างรายการเก็บเงินกับ Omise (PromptPay QR)
// ก่อนบันทึกออเดอร์ — การจ่ายเงินเป็นการบังคับ ไม่มีตัวเลือกจ่ายเงินสดหน้าร้านแล้ว
func (s *Server) CreateOrder(w http.ResponseWriter, r *http.Request) {
	claims, _ := middleware.ClaimsFromContext(r.Context())

	var req createOrderRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if len(req.Items) == 0 {
		httpjson.Error(w, http.StatusBadRequest, "order must contain at least one item")
		return
	}

	vendor, err := s.Store.GetVendorByID(req.VendorID)
	if err != nil {
		httpjson.Error(w, http.StatusNotFound, "stall not found")
		return
	}
	if !vendor.IsOpen {
		httpjson.Error(w, http.StatusConflict, "this stall isn't accepting orders right now")
		return
	}

	// วนตรวจแต่ละรายการที่ลูกค้าเลือก: ต้องเป็นเมนูของร้านนี้จริง ต้องยังมีขายอยู่
	// แล้วคำนวณราคารวมไปพร้อมกัน (snapshot ชื่อ/ราคา ณ ตอนสั่งไว้ในแต่ละรายการ)
	orderItems := make([]models.OrderItem, 0, len(req.Items))
	var total int64
	for _, reqItem := range req.Items {
		if reqItem.Quantity <= 0 {
			httpjson.Error(w, http.StatusBadRequest, "item quantity must be positive")
			return
		}
		menuItem, err := s.Store.GetMenuItem(reqItem.MenuItemID)
		if err != nil || menuItem.VendorID != vendor.ID {
			httpjson.Error(w, http.StatusBadRequest, "one or more menu items are invalid for this stall")
			return
		}
		if !menuItem.IsAvailable {
			httpjson.Error(w, http.StatusConflict, menuItem.Name+" is currently unavailable")
			return
		}

		subtotal := menuItem.PriceCents * int64(reqItem.Quantity)
		total += subtotal
		orderItems = append(orderItems, models.OrderItem{
			MenuItemID:    menuItem.ID,
			NameSnapshot:  menuItem.Name,
			PriceCents:    menuItem.PriceCents,
			Quantity:      reqItem.Quantity,
			SubtotalCents: subtotal,
		})
	}

	// สร้างรายการเก็บเงินกับ Omise ก่อน แล้วค่อยบันทึกออเดอร์ลง store — ถ้า
	// เรียก Omise ไม่สำเร็จ จะไม่มีออเดอร์ค้างอยู่ในระบบเลย (ไม่มี state ครึ่งๆ กลางๆ)
	source, err := s.Omise.CreatePromptPaySource(total, s.Config.PaymentCurrency)
	if err != nil {
		log.Printf("omise: create source failed: %v", err)
		httpjson.Error(w, http.StatusBadGateway, "could not start payment, please try again")
		return
	}
	charge, err := s.Omise.CreateCharge(total, s.Config.PaymentCurrency, source.ID, "FaryHost order: "+vendor.Name)
	if err != nil {
		log.Printf("omise: create charge failed: %v", err)
		httpjson.Error(w, http.StatusBadGateway, "could not start payment, please try again")
		return
	}

	order := &models.Order{
		CustomerID:       claims.UserID,
		VendorID:         vendor.ID,
		Status:           models.OrderAwaitingPayment, // ออเดอร์ใหม่รอลูกค้าจ่ายเงินก่อนเสมอ
		TotalCents:       total,
		Note:             req.Note,
		Items:            orderItems,
		PaymentChargeID:  charge.ID,
		PaymentQRCodeURI: charge.Source.ScannableCode.Image.DownloadURI,
	}
	if err := s.Store.CreateOrder(order); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not place order")
		return
	}
	httpjson.Write(w, http.StatusCreated, order)
}

// ListMyOrders คืนประวัติการสั่งอาหารของลูกค้าที่ login อยู่
func (s *Server) ListMyOrders(w http.ResponseWriter, r *http.Request) {
	claims, _ := middleware.ClaimsFromContext(r.Context())
	httpjson.Write(w, http.StatusOK, s.Store.ListOrdersByCustomer(claims.UserID))
}

// ListVendorOrders คืนออเดอร์ที่เข้ามาที่ร้านค้าของ vendor user ที่ login อยู่
func (s *Server) ListVendorOrders(w http.ResponseWriter, r *http.Request) {
	vendor, ok := s.myVendorOrError(w, r)
	if !ok {
		return
	}
	httpjson.Write(w, http.StatusOK, s.Store.ListOrdersByVendor(vendor.ID))
}

// GetOrder ดูรายละเอียดออเดอร์ 1 รายการ เข้าถึงได้แค่ 2 ฝ่าย: ลูกค้าที่สั่ง
// หรือร้านค้าเจ้าของออเดอร์นั้น (ฝ่ายอื่นจะได้ 404 เหมือนไม่มีออเดอร์นี้อยู่จริง
// เพื่อไม่ให้รู้ด้วยซ้ำว่าออเดอร์นี้มีตัวตน)
func (s *Server) GetOrder(w http.ResponseWriter, r *http.Request) {
	claims, _ := middleware.ClaimsFromContext(r.Context())

	order, err := s.Store.GetOrder(r.PathValue("id"))
	if err != nil {
		httpjson.Error(w, http.StatusNotFound, "order not found")
		return
	}

	if order.CustomerID != claims.UserID {
		vendor, err := s.Store.GetVendorByOwnerID(claims.UserID)
		if err != nil || vendor.ID != order.VendorID {
			httpjson.Error(w, http.StatusNotFound, "order not found")
			return
		}
	}

	// เผื่อ webhook จาก Omise มาไม่ถึง (เช่น รันในเครื่อง dev ที่ยังไม่ได้ตั้งค่า
	// webhook URL สาธารณะ) หน้าจอสถานะออเดอร์ของลูกค้าจะ poll endpoint นี้อยู่
	// แล้ว จึงถือโอกาสเช็คสถานะการจ่ายเงินซ้ำกับ Omise ตรงนี้ไปด้วยเลย
	if order.Status == models.OrderAwaitingPayment {
		order = s.confirmPayment(order)
	}
	httpjson.Write(w, http.StatusOK, order)
}

// confirmPayment เช็คสถานะการจ่ายเงินล่าสุดตรงกับ Omise (ไม่เชื่อข้อมูลจาก
// ที่อื่น) แล้วเปลี่ยนสถานะออเดอร์ให้ตรงถ้าจ่ายเงินสำเร็จ/ล้มเหลว/หมดอายุ
// เรียกได้ทั้งจาก GetOrder (polling fallback) และ OmiseWebhook (fast path)
func (s *Server) confirmPayment(order *models.Order) *models.Order {
	if order.PaymentChargeID == "" {
		return order
	}
	charge, err := s.Omise.GetCharge(order.PaymentChargeID)
	if err != nil {
		log.Printf("omise: get charge %s failed: %v", order.PaymentChargeID, err)
		return order
	}

	var nextStatus models.OrderStatus
	switch charge.Status {
	case omise.ChargeStatusSuccessful:
		nextStatus = models.OrderPending
	case omise.ChargeStatusFailed, omise.ChargeStatusExpired:
		nextStatus = models.OrderCancelled
	default:
		return order // ยังรอลูกค้าจ่ายเงินอยู่ (pending) ไม่ต้องเปลี่ยนอะไร
	}

	updated, err := s.Store.UpdateOrderStatus(order.ID, nextStatus)
	if err != nil {
		log.Printf("omise: could not update order %s after payment confirmation: %v", order.ID, err)
		return order
	}
	return updated
}

// OmiseWebhook รับ event จาก Omise ตอนสถานะการจ่ายเงินเปลี่ยน (public endpoint
// เพราะ Omise เรียกเข้ามาเอง ไม่ได้แนบ JWT มาด้วย)
//
// สำคัญ: Omise ไม่มีลายเซ็นมาให้ตรวจสอบว่า request นี้มาจาก Omise จริงหรือถูก
// ปลอมขึ้นมา (ต่างจาก Stripe's Stripe-Signature header) ดังนั้นห้ามเชื่อ
// สถานะการจ่ายเงินจาก payload ตรงๆ เด็ดขาด handler นี้ใช้ payload แค่หา
// charge ID แล้วเรียกกลับไปถาม Omise เองอีกที (ผ่าน confirmPayment) ก่อน
// จะเปลี่ยนสถานะออเดอร์ใดๆ ทั้งสิ้น
func (s *Server) OmiseWebhook(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	// ใช้ json.NewDecoder ตรงๆ แทน httpjson.Decode เพราะ payload จริงจาก Omise
	// มี field เยอะกว่านี้มาก และเราตั้งใจสนใจแค่ charge ID เท่านั้น
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil || payload.Data.ID == "" {
		httpjson.Error(w, http.StatusBadRequest, "invalid webhook payload")
		return
	}

	order, err := s.Store.GetOrderByChargeID(payload.Data.ID)
	if err != nil {
		// อาจเป็น event ที่ไม่เกี่ยวกับเรา ตอบ 200 ไปเฉยๆ ไม่ต้องให้ Omise ส่งซ้ำ
		httpjson.Write(w, http.StatusOK, nil)
		return
	}
	s.confirmPayment(order)
	httpjson.Write(w, http.StatusOK, nil)
}

type updateOrderStatusRequest struct {
	Status string `json:"status"`
}

// UpdateOrderStatus ให้ร้านค้าเปลี่ยนสถานะออเดอร์ (เช่น กดรับออเดอร์, กำลังทำ,
// พร้อมรับ, เสร็จสิ้น) โดยต้องเป็นออเดอร์ของร้านตัวเอง และเปลี่ยนได้เฉพาะสถานะ
// ที่อนุญาตตาม models.NextStatuses เท่านั้น (ห้ามข้ามขั้นตอน)
func (s *Server) UpdateOrderStatus(w http.ResponseWriter, r *http.Request) {
	vendor, ok := s.myVendorOrError(w, r)
	if !ok {
		return
	}

	order, err := s.Store.GetOrder(r.PathValue("id"))
	if err != nil || order.VendorID != vendor.ID {
		httpjson.Error(w, http.StatusNotFound, "order not found")
		return
	}

	var req updateOrderStatusRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}

	next := models.OrderStatus(req.Status)
	if !isAllowedTransition(order.Status, next) {
		httpjson.Error(w, http.StatusConflict, "cannot move order from \""+string(order.Status)+"\" to \""+req.Status+"\"")
		return
	}

	updated, err := s.Store.UpdateOrderStatus(order.ID, next)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not update order")
		return
	}
	httpjson.Write(w, http.StatusOK, updated)
}

// isAllowedTransition เช็คว่าเปลี่ยนจากสถานะ from ไปสถานะ to ได้ไหม
// โดยดูจากตาราง models.NextStatuses (ตัวเดียวกับที่ฝั่ง Flutter ใช้)
func isAllowedTransition(from, to models.OrderStatus) bool {
	for _, allowed := range models.NextStatuses[from] {
		if allowed == to {
			return true
		}
	}
	return false
}
