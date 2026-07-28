package config

import (
	"os"
	"time"
)

// Config เก็บค่าคอนฟิกที่โหลดมาจาก environment variables ตอนโปรแกรมเริ่มทำงาน
type Config struct {
	Addr      string        // ที่อยู่/พอร์ตที่ HTTP server จะ listen เช่น ":8080"
	JWTSecret []byte        // คีย์ลับสำหรับเซ็น/ตรวจสอบ JWT (ดู internal/authutil)
	TokenTTL  time.Duration // อายุของ JWT ก่อนหมดอายุ ต้อง login ใหม่
}

// Load อ่านค่าคอนฟิกจาก env var ถ้าไม่มีค่าจะใช้ค่า default แทน
func Load() Config {
	return Config{
		Addr:      getEnv("ADDR", ":8080"),
		JWTSecret: []byte(getEnv("JWT_SECRET", "dev-secret-change-me")),
		TokenTTL:  24 * time.Hour,
	}
}

// getEnv คืนค่า env var ตาม key ที่ระบุ ถ้าไม่ได้ตั้งค่าไว้ (ว่างเปล่า) จะคืนค่า fallback แทน
func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
