// Command api รัน HTTP API ของแอปสั่งอาหารล่วงหน้าในตลาดนัด
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

	// เตรียม middleware ไว้ล่วงหน้า แล้วนำไปประกอบ (compose) กับแต่ละ route
	// ด้านล่าง: บาง route เปิดให้ทุกคนเข้าถึงได้ (public), บาง route ต้อง login
	// อย่างเดียว (auth), บาง route ต้อง login และเป็น role ที่กำหนดด้วย
	// (vendorOnly / customerOnly)
	auth := middleware.RequireAuth(cfg.JWTSecret)
	vendorOnly := chain(auth, middleware.RequireRole(string(models.RoleVendor)))
	customerOnly := chain(auth, middleware.RequireRole(string(models.RoleCustomer)))

	// Auth (public: ยังไม่ login ก็เรียกได้)
	mux.HandleFunc("POST /api/auth/register", s.Register)
	mux.HandleFunc("POST /api/auth/login", s.Login)

	// Vendors (public: ลูกค้าดูร้านค้า/เมนูได้โดยไม่ต้อง login)
	mux.HandleFunc("GET /api/vendors", s.ListVendors)
	mux.HandleFunc("GET /api/vendors/{id}", s.GetVendorDetail)

	// จัดการร้านค้าของตัวเอง (ต้อง login เป็น vendor)
	mux.Handle("POST /api/vendors/me", vendorOnly(http.HandlerFunc(s.CreateVendor)))
	mux.Handle("GET /api/vendors/me", vendorOnly(http.HandlerFunc(s.GetMyVendor)))
	mux.Handle("PATCH /api/vendors/me", vendorOnly(http.HandlerFunc(s.UpdateMyVendor)))
	mux.Handle("GET /api/vendors/me/orders", vendorOnly(http.HandlerFunc(s.ListVendorOrders)))

	// จัดการเมนูของร้านตัวเอง (ต้อง login เป็น vendor)
	mux.Handle("POST /api/vendors/me/menu-items", vendorOnly(http.HandlerFunc(s.CreateMenuItem)))
	mux.Handle("GET /api/vendors/me/menu-items", vendorOnly(http.HandlerFunc(s.ListMyMenuItems)))
	mux.Handle("PATCH /api/vendors/me/menu-items/{id}", vendorOnly(http.HandlerFunc(s.UpdateMenuItem)))
	mux.Handle("DELETE /api/vendors/me/menu-items/{id}", vendorOnly(http.HandlerFunc(s.DeleteMenuItem)))

	// ออเดอร์
	mux.Handle("POST /api/orders", customerOnly(http.HandlerFunc(s.CreateOrder)))
	mux.Handle("GET /api/orders/me", customerOnly(http.HandlerFunc(s.ListMyOrders)))
	mux.Handle("GET /api/orders/{id}", auth(http.HandlerFunc(s.GetOrder))) // ลูกค้าหรือร้านค้าก็เรียกได้ เช็คสิทธิ์ในตัว handler เอง
	mux.Handle("PATCH /api/orders/{id}/status", vendorOnly(http.HandlerFunc(s.UpdateOrderStatus)))

	// ห่อทั้ง mux ด้วย logging กับ CORS อีกชั้นนอกสุด (ใช้กับทุก route)
	handler := middleware.Logging(middleware.CORS(mux))

	log.Printf("FaryHost API listening on %s", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, handler); err != nil {
		log.Fatal(err)
	}
}

// chain ต่อ middleware หลายตัวเข้าด้วยกันจากซ้ายไปขวา: chain(a, b)(h) == a(b(h))
// เช่น chain(auth, requireVendorRole) จะเช็ค auth ก่อน แล้วค่อยเช็ค role ทีหลัง
func chain(mws ...func(http.Handler) http.Handler) func(http.Handler) http.Handler {
	return func(final http.Handler) http.Handler {
		for i := len(mws) - 1; i >= 0; i-- {
			final = mws[i](final)
		}
		return final
	}
}
