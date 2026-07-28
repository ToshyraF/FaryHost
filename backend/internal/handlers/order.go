package handlers

import (
	"net/http"

	"github.com/ToshyraF/FaryHost/backend/internal/httpjson"
	"github.com/ToshyraF/FaryHost/backend/internal/middleware"
	"github.com/ToshyraF/FaryHost/backend/internal/models"
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
// ออเดอร์เก่าที่สั่งไปแล้ว
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

	order := &models.Order{
		CustomerID: claims.UserID,
		VendorID:   vendor.ID,
		Status:     models.OrderPending, // ออเดอร์ใหม่เริ่มที่สถานะ "รอร้านรับ" เสมอ
		TotalCents: total,
		Note:       req.Note,
		Items:      orderItems,
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
	httpjson.Write(w, http.StatusOK, order)
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
