// Command api runs the FaryHost market pre-order HTTP API.
package main

import (
	"log"
	"net/http"

	"github.com/ToshyraF/FaryHost/backend/internal/config"
	"github.com/ToshyraF/FaryHost/backend/internal/handlers"
	"github.com/ToshyraF/FaryHost/backend/internal/middleware"
	"github.com/ToshyraF/FaryHost/backend/internal/models"
	"github.com/ToshyraF/FaryHost/backend/internal/store"
)

func main() {
	cfg := config.Load()
	s := handlers.New(store.New(), cfg)

	mux := http.NewServeMux()

	auth := middleware.RequireAuth(cfg.JWTSecret)
	vendorOnly := chain(auth, middleware.RequireRole(string(models.RoleVendor)))
	customerOnly := chain(auth, middleware.RequireRole(string(models.RoleCustomer)))

	// Auth
	mux.HandleFunc("POST /api/auth/register", s.Register)
	mux.HandleFunc("POST /api/auth/login", s.Login)

	// Vendors (public browsing)
	mux.HandleFunc("GET /api/vendors", s.ListVendors)
	mux.HandleFunc("GET /api/vendors/{id}", s.GetVendorDetail)

	// Vendor's own stall management
	mux.Handle("POST /api/vendors/me", vendorOnly(http.HandlerFunc(s.CreateVendor)))
	mux.Handle("GET /api/vendors/me", vendorOnly(http.HandlerFunc(s.GetMyVendor)))
	mux.Handle("PATCH /api/vendors/me", vendorOnly(http.HandlerFunc(s.UpdateMyVendor)))
	mux.Handle("GET /api/vendors/me/orders", vendorOnly(http.HandlerFunc(s.ListVendorOrders)))

	// Vendor's own menu management
	mux.Handle("POST /api/vendors/me/menu-items", vendorOnly(http.HandlerFunc(s.CreateMenuItem)))
	mux.Handle("GET /api/vendors/me/menu-items", vendorOnly(http.HandlerFunc(s.ListMyMenuItems)))
	mux.Handle("PATCH /api/vendors/me/menu-items/{id}", vendorOnly(http.HandlerFunc(s.UpdateMenuItem)))
	mux.Handle("DELETE /api/vendors/me/menu-items/{id}", vendorOnly(http.HandlerFunc(s.DeleteMenuItem)))

	// Orders
	mux.Handle("POST /api/orders", customerOnly(http.HandlerFunc(s.CreateOrder)))
	mux.Handle("GET /api/orders/me", customerOnly(http.HandlerFunc(s.ListMyOrders)))
	mux.Handle("GET /api/orders/{id}", auth(http.HandlerFunc(s.GetOrder)))
	mux.Handle("PATCH /api/orders/{id}/status", vendorOnly(http.HandlerFunc(s.UpdateOrderStatus)))

	handler := middleware.Logging(middleware.CORS(mux))

	log.Printf("FaryHost API listening on %s", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, handler); err != nil {
		log.Fatal(err)
	}
}

// chain composes middleware left-to-right: chain(a, b)(h) == a(b(h)).
func chain(mws ...func(http.Handler) http.Handler) func(http.Handler) http.Handler {
	return func(final http.Handler) http.Handler {
		for i := len(mws) - 1; i >= 0; i-- {
			final = mws[i](final)
		}
		return final
	}
}
