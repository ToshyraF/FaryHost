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
	IsOpen      *bool  `json:"is_open"`
}

// CreateVendor sets up the stall profile for the authenticated vendor user.
// Each vendor user may own exactly one stall.
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
		IsOpen:      true,
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

func (s *Server) GetMyVendor(w http.ResponseWriter, r *http.Request) {
	claims, _ := middleware.ClaimsFromContext(r.Context())

	vendor, err := s.Store.GetVendorByOwnerID(claims.UserID)
	if err != nil {
		httpjson.Error(w, http.StatusNotFound, "you haven't set up a stall yet")
		return
	}
	httpjson.Write(w, http.StatusOK, vendor)
}

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

// ListVendors is public: customers browse stalls without logging in.
func (s *Server) ListVendors(w http.ResponseWriter, r *http.Request) {
	httpjson.Write(w, http.StatusOK, s.Store.ListVendors())
}

type vendorDetail struct {
	models.Vendor
	MenuItems []*models.MenuItem `json:"menu_items"`
}

// GetVendorDetail is public: a stall's profile plus its menu.
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

// --- Menu items (managed by the owning vendor) ---

type menuItemRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceCents  int64  `json:"price_cents"`
	IsAvailable *bool  `json:"is_available"`
}

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

func (s *Server) ListMyMenuItems(w http.ResponseWriter, r *http.Request) {
	vendor, ok := s.myVendorOrError(w, r)
	if !ok {
		return
	}
	httpjson.Write(w, http.StatusOK, s.Store.ListMenuItemsByVendor(vendor.ID))
}

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

// myVendorOrError resolves the authenticated user's stall, writing a 404
// response and returning ok=false if they haven't set one up yet.
func (s *Server) myVendorOrError(w http.ResponseWriter, r *http.Request) (*models.Vendor, bool) {
	claims, _ := middleware.ClaimsFromContext(r.Context())
	vendor, err := s.Store.GetVendorByOwnerID(claims.UserID)
	if err != nil {
		httpjson.Error(w, http.StatusNotFound, "you haven't set up a stall yet")
		return nil, false
	}
	return vendor, true
}
