package handlers

import (
	"errors"
	"net/http"

	"github.com/ToshyraF/FaryHost/backend/internal/httpjson"
	"github.com/ToshyraF/FaryHost/backend/internal/middleware"
	"github.com/ToshyraF/FaryHost/backend/internal/models"
	"github.com/ToshyraF/FaryHost/backend/internal/store"
)

type vendorRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	StallNumber string `json:"stall_number"`
	MarketZone  string `json:"market_zone"`
	IsOpen      *bool  `json:"is_open"` // pointer เพื่อแยกได้ว่า "ไม่ได้ส่งค่ามา" กับ "ส่งค่า false มา"
}

// CreateVendor ตั้งค่าโปรไฟล์ร้านค้าให้กับ vendor user ที่ login อยู่
// vendor user แต่ละคนเปิดร้านได้แค่ 1 ร้านเท่านั้น
func (s *Server) CreateVendor(w http.ResponseWriter, r *http.Request) {
	claims, _ := middleware.ClaimsFromContext(r.Context())

	var req vendorRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Name == "" {
		httpjson.Error(w, http.StatusBadRequest, "name is required")
		return
	}

	vendor := &models.Vendor{
		OwnerUserID: claims.UserID,
		Name:        req.Name,
		Description: req.Description,
		StallNumber: req.StallNumber,
		MarketZone:  req.MarketZone,
		IsOpen:      true, // ร้านใหม่เปิดรับออเดอร์ทันทีโดย default
	}
	if err := s.Store.CreateVendor(vendor); err != nil {
		if errors.Is(err, store.ErrConflict) {
			httpjson.Error(w, http.StatusConflict, "you already have a stall set up")
			return
		}
		httpjson.Error(w, http.StatusInternalServerError, "could not create stall")
		return
	}
	httpjson.Write(w, http.StatusCreated, vendor)
}

// GetMyVendor คืนร้านค้าของ vendor user ที่ login อยู่
// ฝั่ง Flutter ใช้ endpoint นี้เช็คว่าร้านค้าเคยตั้งค่าไว้หรือยัง
// (ถ้ายังไม่มี = แสดงฟอร์มตั้งค่าร้านแทน dashboard)
func (s *Server) GetMyVendor(w http.ResponseWriter, r *http.Request) {
	claims, _ := middleware.ClaimsFromContext(r.Context())

	vendor, err := s.Store.GetVendorByOwnerID(claims.UserID)
	if err != nil {
		httpjson.Error(w, http.StatusNotFound, "you haven't set up a stall yet")
		return
	}
	httpjson.Write(w, http.StatusOK, vendor)
}

// UpdateMyVendor แก้ไขข้อมูลร้านค้า (ชื่อ, รายละเอียด, เลขล็อค, โซน, เปิด/ปิดรับออเดอร์)
func (s *Server) UpdateMyVendor(w http.ResponseWriter, r *http.Request) {
	claims, _ := middleware.ClaimsFromContext(r.Context())

	vendor, err := s.Store.GetVendorByOwnerID(claims.UserID)
	if err != nil {
		httpjson.Error(w, http.StatusNotFound, "you haven't set up a stall yet")
		return
	}

	var req vendorRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Name != "" {
		vendor.Name = req.Name
	}
	vendor.Description = req.Description
	vendor.StallNumber = req.StallNumber
	vendor.MarketZone = req.MarketZone
	if req.IsOpen != nil {
		vendor.IsOpen = *req.IsOpen
	}

	if err := s.Store.UpdateVendor(vendor); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not update stall")
		return
	}
	httpjson.Write(w, http.StatusOK, vendor)
}

// ListVendors เป็น public endpoint: ลูกค้าดูรายชื่อร้านค้าได้โดยไม่ต้อง login
func (s *Server) ListVendors(w http.ResponseWriter, r *http.Request) {
	httpjson.Write(w, http.StatusOK, s.Store.ListVendors())
}

// vendorDetail รวมข้อมูลร้านค้า + เมนูทั้งหมด ไว้ในก้อนเดียว เพื่อให้หน้าเมนูร้านค้า
// ของฝั่งลูกค้าเรียก API แค่ครั้งเดียวจบ
type vendorDetail struct {
	models.Vendor
	MenuItems []*models.MenuItem `json:"menu_items"`
}

// GetVendorDetail เป็น public endpoint: ดูโปรไฟล์ร้านค้าพร้อมเมนูทั้งหมดได้โดยไม่ต้อง login
func (s *Server) GetVendorDetail(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")

	vendor, err := s.Store.GetVendorByID(id)
	if err != nil {
		httpjson.Error(w, http.StatusNotFound, "stall not found")
		return
	}

	httpjson.Write(w, http.StatusOK, vendorDetail{
		Vendor:    *vendor,
		MenuItems: s.Store.ListMenuItemsByVendor(vendor.ID),
	})
}

// --- Menu items (จัดการได้เฉพาะร้านค้าเจ้าของเมนูนั้นๆ) ---

type menuItemRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceCents  int64  `json:"price_cents"`
	IsAvailable *bool  `json:"is_available"`
}

// CreateMenuItem เพิ่มเมนูใหม่ให้ร้านค้าของตัวเอง (เมนูใหม่ตั้งเป็น "มีขาย" โดย default)
func (s *Server) CreateMenuItem(w http.ResponseWriter, r *http.Request) {
	vendor, ok := s.myVendorOrError(w, r)
	if !ok {
		return
	}

	var req menuItemRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Name == "" || req.PriceCents <= 0 {
		httpjson.Error(w, http.StatusBadRequest, "name and a positive price_cents are required")
		return
	}

	item := &models.MenuItem{
		VendorID:    vendor.ID,
		Name:        req.Name,
		Description: req.Description,
		PriceCents:  req.PriceCents,
		IsAvailable: true,
	}
	if req.IsAvailable != nil {
		item.IsAvailable = *req.IsAvailable
	}
	if err := s.Store.CreateMenuItem(item); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not create menu item")
		return
	}
	httpjson.Write(w, http.StatusCreated, item)
}

// ListMyMenuItems คืนเมนูทั้งหมดของร้านตัวเอง (สำหรับหน้าจัดการเมนูของร้านค้า)
func (s *Server) ListMyMenuItems(w http.ResponseWriter, r *http.Request) {
	vendor, ok := s.myVendorOrError(w, r)
	if !ok {
		return
	}
	httpjson.Write(w, http.StatusOK, s.Store.ListMenuItemsByVendor(vendor.ID))
}

// UpdateMenuItem แก้ไขเมนู (ต้องเป็นเมนูของร้านตัวเองเท่านั้น ห้ามแก้เมนูร้านอื่น)
func (s *Server) UpdateMenuItem(w http.ResponseWriter, r *http.Request) {
	vendor, ok := s.myVendorOrError(w, r)
	if !ok {
		return
	}

	item, err := s.Store.GetMenuItem(r.PathValue("id"))
	if err != nil || item.VendorID != vendor.ID {
		httpjson.Error(w, http.StatusNotFound, "menu item not found")
		return
	}

	var req menuItemRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Name != "" {
		item.Name = req.Name
	}
	item.Description = req.Description
	if req.PriceCents > 0 {
		item.PriceCents = req.PriceCents
	}
	if req.IsAvailable != nil {
		item.IsAvailable = *req.IsAvailable
	}

	if err := s.Store.UpdateMenuItem(item); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not update menu item")
		return
	}
	httpjson.Write(w, http.StatusOK, item)
}

// DeleteMenuItem ลบเมนู (ต้องเป็นเมนูของร้านตัวเองเท่านั้น)
func (s *Server) DeleteMenuItem(w http.ResponseWriter, r *http.Request) {
	vendor, ok := s.myVendorOrError(w, r)
	if !ok {
		return
	}

	item, err := s.Store.GetMenuItem(r.PathValue("id"))
	if err != nil || item.VendorID != vendor.ID {
		httpjson.Error(w, http.StatusNotFound, "menu item not found")
		return
	}

	if err := s.Store.DeleteMenuItem(item.ID); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not delete menu item")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// myVendorOrError หาร้านค้าของผู้ใช้ที่ login อยู่ ถ้ายังไม่เคยตั้งค่าร้านไว้
// จะเขียน response 404 ให้เลยแล้วคืน ok=false (handler ที่เรียกต้องจบการทำงานทันที)
func (s *Server) myVendorOrError(w http.ResponseWriter, r *http.Request) (*models.Vendor, bool) {
	claims, _ := middleware.ClaimsFromContext(r.Context())
	vendor, err := s.Store.GetVendorByOwnerID(claims.UserID)
	if err != nil {
		httpjson.Error(w, http.StatusNotFound, "you haven't set up a stall yet")
		return nil, false
	}
	return vendor, true
}
