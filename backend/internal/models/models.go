package models

import "time"

type Role string

const (
	RoleCustomer Role = "customer"
	RoleVendor   Role = "vendor"
)

type OrderStatus string

const (
	OrderPending   OrderStatus = "pending"
	OrderAccepted  OrderStatus = "accepted"
	OrderPreparing OrderStatus = "preparing"
	OrderReady     OrderStatus = "ready"
	OrderCompleted OrderStatus = "completed"
	OrderCancelled OrderStatus = "cancelled"
)

// NextStatuses defines which status transitions a vendor may make.
var NextStatuses = map[OrderStatus][]OrderStatus{
	OrderPending:   {OrderAccepted, OrderCancelled},
	OrderAccepted:  {OrderPreparing, OrderCancelled},
	OrderPreparing: {OrderReady, OrderCancelled},
	OrderReady:     {OrderCompleted},
}

type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	FullName     string    `json:"full_name"`
	Phone        string    `json:"phone,omitempty"`
	Role         Role      `json:"role"`
	CreatedAt    time.Time `json:"created_at"`
}

type Vendor struct {
	ID          string    `json:"id"`
	OwnerUserID string    `json:"owner_user_id"`
	Name        string    `json:"name"`
	Description string    `json:"description,omitempty"`
	StallNumber string    `json:"stall_number,omitempty"`
	MarketZone  string    `json:"market_zone,omitempty"`
	IsOpen      bool      `json:"is_open"`
	CreatedAt   time.Time `json:"created_at"`
}

type MenuItem struct {
	ID          string    `json:"id"`
	VendorID    string    `json:"vendor_id"`
	Name        string    `json:"name"`
	Description string    `json:"description,omitempty"`
	PriceCents  int64     `json:"price_cents"`
	IsAvailable bool      `json:"is_available"`
	CreatedAt   time.Time `json:"created_at"`
}

type OrderItem struct {
	ID            string `json:"id"`
	OrderID       string `json:"order_id"`
	MenuItemID    string `json:"menu_item_id"`
	NameSnapshot  string `json:"name_snapshot"`
	PriceCents    int64  `json:"price_cents"`
	Quantity      int    `json:"quantity"`
	SubtotalCents int64  `json:"subtotal_cents"`
}

type Order struct {
	ID         string      `json:"id"`
	Code       string      `json:"code"`
	CustomerID string      `json:"customer_id"`
	VendorID   string      `json:"vendor_id"`
	Status     OrderStatus `json:"status"`
	TotalCents int64       `json:"total_cents"`
	Note       string      `json:"note,omitempty"`
	Items      []OrderItem `json:"items"`
	CreatedAt  time.Time   `json:"created_at"`
	UpdatedAt  time.Time   `json:"updated_at"`
}
