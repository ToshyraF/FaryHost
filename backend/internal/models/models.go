package models

import "time"

// Role คือบทบาทของผู้ใช้งาน มีแค่ 2 แบบ: ลูกค้า (customer) กับร้านค้า (vendor)
type Role string

const (
	RoleCustomer Role = "customer"
	RoleVendor   Role = "vendor"
)

// OrderStatus คือสถานะของออเดอร์ในแต่ละขั้นตอน
type OrderStatus string

const (
	OrderAwaitingPayment OrderStatus = "awaiting_payment" // สร้างออเดอร์แล้ว รอลูกค้าสแกน QR จ่ายเงินให้เสร็จก่อน
	OrderPending         OrderStatus = "pending"          // จ่ายเงินสำเร็จแล้ว รอร้านค้ากดรับออเดอร์
	OrderAccepted        OrderStatus = "accepted"         // ร้านค้ารับออเดอร์แล้ว
	OrderPreparing       OrderStatus = "preparing"        // ร้านค้ากำลังทำอาหาร
	OrderReady           OrderStatus = "ready"            // อาหารเสร็จแล้ว พร้อมให้ลูกค้ามารับ
	OrderCompleted       OrderStatus = "completed"        // ลูกค้ามารับอาหารเรียบร้อยแล้ว (สถานะจบ)
	OrderCancelled       OrderStatus = "cancelled"        // ออเดอร์ถูกยกเลิก (สถานะจบ)
)

// NextStatuses กำหนดว่าจากสถานะปัจจุบัน ร้านค้าสามารถเปลี่ยนไปสถานะไหนต่อได้บ้าง
// (ห้ามข้ามขั้นตอน เช่น จาก pending จะกระโดดไป ready เลยไม่ได้)
// ทั้ง backend (handlers.isAllowedTransition) และฝั่ง Flutter
// (lib/core/models/order.dart) ต้องใช้กติกาเดียวกันนี้ ถ้าแก้ต้องแก้ทั้งคู่
//
// หมายเหตุ: การเปลี่ยนจาก OrderAwaitingPayment -> OrderPending ไม่ได้อยู่ใน
// ตารางนี้ เพราะไม่ใช่การกระทำของร้านค้า แต่เป็นระบบเปลี่ยนให้อัตโนมัติ
// ทันทีที่ยืนยันกับ Omise ได้ว่าจ่ายเงินสำเร็จแล้ว (ดู handlers.confirmPayment)
// ร้านค้าทำได้แค่ยกเลิกออเดอร์ที่ยังไม่จ่ายเงินเท่านั้น
var NextStatuses = map[OrderStatus][]OrderStatus{
	OrderAwaitingPayment: {OrderCancelled},
	OrderPending:         {OrderAccepted, OrderCancelled},
	OrderAccepted:        {OrderPreparing, OrderCancelled},
	OrderPreparing:       {OrderReady, OrderCancelled},
	OrderReady:           {OrderCompleted},
	// OrderCompleted และ OrderCancelled เป็นสถานะจบ ไม่มีขั้นต่อไปแล้ว
}

// User คือบัญชีผู้ใช้ (ทั้งลูกค้าและร้านค้าใช้ตารางเดียวกัน แยกกันด้วย Role)
type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"` // ไม่ส่งค่านี้กลับไปใน JSON response เด็ดขาด
	FullName     string    `json:"full_name"`
	Phone        string    `json:"phone,omitempty"`
	Role         Role      `json:"role"`
	CreatedAt    time.Time `json:"created_at"`
}

// Vendor คือร้านค้า/แผงขายของในตลาดนัด ผู้ใช้ 1 คน (role=vendor) เปิดร้านได้แค่ 1 ร้าน
type Vendor struct {
	ID          string    `json:"id"`
	OwnerUserID string    `json:"owner_user_id"`
	Name        string    `json:"name"`
	Description string    `json:"description,omitempty"`
	StallNumber string    `json:"stall_number,omitempty"` // เลขล็อค/แผง
	MarketZone  string    `json:"market_zone,omitempty"`  // โซนในตลาด
	IsOpen      bool      `json:"is_open"`                // ถ้าปิด (false) ลูกค้าจะสั่งอาหารไม่ได้
	CreatedAt   time.Time `json:"created_at"`
}

// MenuItem คือเมนูอาหารของร้านค้าแต่ละร้าน
type MenuItem struct {
	ID          string    `json:"id"`
	VendorID    string    `json:"vendor_id"`
	Name        string    `json:"name"`
	Description string    `json:"description,omitempty"`
	PriceCents  int64     `json:"price_cents"` // ราคาเก็บเป็นหน่วยสตางค์ (จำนวนเต็ม) เพื่อเลี่ยงปัญหาความคลาดเคลื่อนของ float
	IsAvailable bool      `json:"is_available"`
	CreatedAt   time.Time `json:"created_at"`
}

// OrderItem คือรายการสินค้าแต่ละชิ้นในออเดอร์
// เก็บชื่อ/ราคาแบบ "snapshot" ไว้ ณ ตอนสั่ง เพื่อไม่ให้การแก้เมนูในภายหลัง
// (เช่น ร้านค้าขึ้นราคา) ไปกระทบยอดเงินของออเดอร์เก่าที่สั่งไปแล้ว
type OrderItem struct {
	ID            string `json:"id"`
	OrderID       string `json:"order_id"`
	MenuItemID    string `json:"menu_item_id"`
	NameSnapshot  string `json:"name_snapshot"`
	PriceCents    int64  `json:"price_cents"`
	Quantity      int    `json:"quantity"`
	SubtotalCents int64  `json:"subtotal_cents"` // = PriceCents * Quantity
}

// Order คือคำสั่งซื้อของลูกค้า 1 ออเดอร์ (สั่งได้ทีละร้านเดียว)
// การจ่ายเงินเป็นแบบบังคับผ่าน Omise PromptPay QR (ดู internal/omise) ไม่มี
// ทางเลือกจ่ายเงินสดหน้าร้านแล้ว
type Order struct {
	ID         string      `json:"id"`
	Code       string      `json:"code"` // รหัสสั้นๆ ที่ลูกค้าใช้แสดงหน้าร้านตอนมารับอาหาร
	CustomerID string      `json:"customer_id"`
	VendorID   string      `json:"vendor_id"`
	Status     OrderStatus `json:"status"`
	TotalCents int64       `json:"total_cents"` // ยอดรวมทั้งออเดอร์ (ผลรวมของ SubtotalCents ทุกรายการ)
	Note       string      `json:"note,omitempty"`
	Items      []OrderItem `json:"items"`

	// PaymentChargeID คือ ID ของ Omise charge ที่ผูกกับออเดอร์นี้ ใช้ตอน
	// ยืนยันสถานะการจ่ายเงินย้อนกลับไปที่ Omise (ทั้งตอน webhook มาถึงและ
	// ตอน GetOrder ถูกเรียกซ้ำๆ ระหว่างที่ลูกค้ายังไม่จ่ายเงิน)
	PaymentChargeID string `json:"-"`
	// PaymentQRCodeURI คือ URL รูป QR code ให้ลูกค้าสแกนจ่ายเงิน มีค่าเฉพาะ
	// ตอนสถานะเป็น OrderAwaitingPayment เท่านั้น
	PaymentQRCodeURI string `json:"payment_qr_code_uri,omitempty"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
