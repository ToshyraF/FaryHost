// Package idgen สร้าง ID โดยใช้แค่ standard library เท่านั้น เพราะ module นี้
// ไม่มี external dependency เลย (ดูเหตุผลใน backend/README.md)
package idgen

import (
	"crypto/rand"
	"fmt"
)

// UUID คืนค่า UUIDv4 แบบสุ่ม (เขียนเองแทนการใช้ library google/uuid)
func UUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	b[6] = (b[6] & 0x0f) | 0x40 // ตั้งค่า version เป็น 4
	b[8] = (b[8] & 0x3f) | 0x80 // ตั้งค่า variant เป็น 10 (RFC 4122)
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// ตัดตัวอักษรที่มักอ่านสับสน (0/O, 1/I) ออก เพื่อให้รหัสรับอาหารอ่านง่ายเวลาพูดหรือพิมพ์
const pickupCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

// PickupCode คืนรหัสสั้นๆ ที่เป็นมิตรกับผู้ใช้ (เช่น "K7X4Q9")
// ที่ลูกค้าใช้แสดงหน้าร้านค้าตอนไปรับอาหาร
func PickupCode() string {
	const length = 6
	out := make([]byte, length)
	buf := make([]byte, length)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	for i, c := range buf {
		out[i] = pickupCodeAlphabet[int(c)%len(pickupCodeAlphabet)]
	}
	return string(out)
}
