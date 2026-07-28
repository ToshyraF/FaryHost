// Package httpjson รวมฟังก์ชันช่วยเหลือเล็กๆ สำหรับเขียน/อ่าน JSON ผ่าน
// net/http ซึ่ง handler ทุกตัวใน internal/handlers ใช้ร่วมกัน
package httpjson

import (
	"encoding/json"
	"net/http"
)

// Write ตั้งค่า Content-Type, เขียน HTTP status code แล้วเข้ารหัส body เป็น JSON ส่งกลับ
func Write(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if body != nil {
		_ = json.NewEncoder(w).Encode(body)
	}
}

// Error ส่ง response รูปแบบ {"error": "..."} กลับไป พร้อม status code ที่ระบุ
func Error(w http.ResponseWriter, status int, message string) {
	Write(w, status, map[string]string{"error": message})
}

// Decode อ่าน request body เป็น JSON ใส่ลงใน dst
// ใช้ DisallowUnknownFields เพื่อปฏิเสธ field แปลกปลอมที่ไม่รู้จัก ช่วยจับ typo
// ของฝั่ง client ได้ตั้งแต่เนิ่นๆ แทนที่จะเงียบๆ ละเลยไป
func Decode(r *http.Request, dst any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}
