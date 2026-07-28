// Package handlers รวม HTTP handler ทั้งหมด: รับ request, ตรวจสอบความถูกต้อง
// (validation) แล้วแปลงผลลัพธ์จาก store ให้เป็น JSON response
package handlers

import (
	"github.com/ToshyraF/FaryHost/backend/internal/config"
	"github.com/ToshyraF/FaryHost/backend/internal/store"
)

// Server ถือ dependency ที่ handler ทุกตัวต้องใช้ร่วมกัน (store ข้อมูล + config)
// handler แต่ละตัวคือ method ของ *Server
type Server struct {
	Store  *store.Store
	Config config.Config
}

func New(s *store.Store, cfg config.Config) *Server {
	return &Server{Store: s, Config: cfg}
}
