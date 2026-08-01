// Package authutil ทำหน้าที่ hash รหัสผ่าน และออก/ตรวจสอบ JWT โดยใช้แค่
// standard library (crypto/hmac, crypto/sha256) เพราะ module นี้ตั้งใจไม่มี
// external dependency เลย — ดู backend/README.md
package authutil

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"strconv"
	"strings"
)

const (
	pbkdf2Iterations = 100_000 // ยิ่งเยอะยิ่ง brute-force ยาก แต่ก็ช้าลงตาม
	saltLen          = 16      // ความยาว salt แบบสุ่ม (ไบต์) กันไม่ให้ hash เดิมซ้ำกันแม้รหัสผ่านเหมือนกัน
	keyLen           = 32      // ความยาว hash ที่ได้ (ไบต์)
)

// HashPassword สร้าง salt แบบสุ่ม แล้ว hash รหัสผ่านด้วย PBKDF2-HMAC-SHA256
// เก็บผลลัพธ์เป็น string รูปแบบ "pbkdf2$iterations$saltB64$hashB64"
// เพื่อให้ตรวจสอบย้อนหลังได้แม้จะเปลี่ยนค่า iterations ในอนาคต
func HashPassword(password string) (string, error) {
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	hash := pbkdf2(password, salt, pbkdf2Iterations, keyLen)
	return fmt.Sprintf("pbkdf2$%d$%s$%s",
		pbkdf2Iterations,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	), nil
}

// VerifyPassword เช็ครหัสผ่านที่ผู้ใช้กรอก เทียบกับ hash ที่เก็บไว้จาก HashPassword
func VerifyPassword(encoded, password string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 || parts[0] != "pbkdf2" {
		return false
	}
	iterations, err := strconv.Atoi(parts[1])
	if err != nil {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[2])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[3])
	if err != nil {
		return false
	}
	got := pbkdf2(password, salt, iterations, len(want))
	// ใช้ hmac.Equal แทน == ธรรมดา เพื่อป้องกัน timing attack (เวลาที่ใช้เปรียบเทียบ
	// ต้องคงที่ ไม่ขึ้นกับว่าไบต์ตรงกันกี่ตัว)
	return hmac.Equal(got, want)
}

// pbkdf2 คือการเขียน RFC 8018 PBKDF2 ด้วย HMAC-SHA256 เอง เพื่อเลี่ยงการ
// import golang.org/x/crypto/pbkdf2 ซึ่งเป็น external dependency
func pbkdf2(password string, salt []byte, iterations, keyLen int) []byte {
	hashLen := sha256.Size
	numBlocks := (keyLen + hashLen - 1) / hashLen // ปัดขึ้น ถ้า keyLen ไม่ลงตัวพอดีกับ hashLen

	out := make([]byte, 0, numBlocks*hashLen)
	for block := 1; block <= numBlocks; block++ {
		out = append(out, pbkdf2Block(password, salt, iterations, block)...)
	}
	return out[:keyLen]
}

// pbkdf2Block คำนวณ "บล็อก" ที่ 1 ตัวของ PBKDF2: ทำ HMAC ซ้ำๆ ตามจำนวน
// iterations แล้ว XOR ผลลัพธ์แต่ละรอบเข้าด้วยกัน (ตามสเปก RFC 8018)
func pbkdf2Block(password string, salt []byte, iterations, blockIndex int) []byte {
	mac := hmac.New(sha256.New, []byte(password))

	// รอบแรก: HMAC(password, salt || blockIndex แบบ big-endian 4 ไบต์)
	blockNum := make([]byte, 4)
	binary.BigEndian.PutUint32(blockNum, uint32(blockIndex))
	mac.Write(salt)
	mac.Write(blockNum)
	u := mac.Sum(nil)

	result := make([]byte, len(u))
	copy(result, u)

	// รอบที่เหลือ: HMAC(password, ผลลัพธ์รอบก่อนหน้า) แล้ว XOR สะสมเข้า result
	for i := 1; i < iterations; i++ {
		mac.Reset()
		mac.Write(u)
		u = mac.Sum(nil)
		for j := range result {
			result[j] ^= u[j]
		}
	}
	return result
}
