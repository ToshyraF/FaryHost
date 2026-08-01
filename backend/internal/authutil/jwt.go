package authutil

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

var (
	ErrInvalidToken = errors.New("invalid token")
	ErrExpiredToken = errors.New("token expired")
)

// Claims คือข้อมูลที่ฝังอยู่ใน JWT: ใครเป็นคนออกโทเคน (UserID) บทบาทอะไร (Role)
// และหมดอายุเมื่อไหร่ (Exp เป็น Unix timestamp)
type Claims struct {
	UserID string `json:"sub"`
	Role   string `json:"role"`
	Exp    int64  `json:"exp"`
}

type jwtHeader struct {
	Alg string `json:"alg"`
	Typ string `json:"typ"`
}

// GenerateToken ออก JWT แบบ HS256 (HMAC-SHA256) ที่เก็บ user ID กับ role ไว้
// เขียนเอง (แทน golang-jwt/jwt) เพื่อให้ module นี้ไม่มี external dependency
// — ดู backend/README.md
//
// โครงสร้างของ JWT คือ 3 ส่วนคั่นด้วยจุด: base64url(header).base64url(payload).base64url(signature)
// โดย signature คือ HMAC-SHA256(header+"."+payload, secret) เพื่อพิสูจน์ว่า
// โทเคนนี้ server เราเป็นคนออกเอง ไม่มีใครปลอมได้ถ้าไม่รู้ secret
func GenerateToken(userID, role string, secret []byte, ttl time.Duration) (string, error) {
	header := jwtHeader{Alg: "HS256", Typ: "JWT"}
	claims := Claims{UserID: userID, Role: role, Exp: time.Now().Add(ttl).Unix()}

	headerJSON, err := json.Marshal(header)
	if err != nil {
		return "", err
	}
	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}

	signingInput := b64(headerJSON) + "." + b64(claimsJSON)
	sig := sign(signingInput, secret)
	return signingInput + "." + b64(sig), nil
}

// ParseToken ตรวจสอบลายเซ็นและวันหมดอายุของ token ที่ออกโดย GenerateToken
// แล้วคืนค่า claims ที่ฝังอยู่ข้างในกลับมา
func ParseToken(token string, secret []byte) (*Claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, ErrInvalidToken
	}
	signingInput := parts[0] + "." + parts[1]
	expectedSig := sign(signingInput, secret)

	gotSig, err := unb64(parts[2])
	if err != nil {
		return nil, ErrInvalidToken
	}
	// เทียบลายเซ็นด้วย hmac.Equal (constant-time) กัน timing attack
	if !hmac.Equal(gotSig, expectedSig) {
		return nil, ErrInvalidToken
	}

	claimsJSON, err := unb64(parts[1])
	if err != nil {
		return nil, ErrInvalidToken
	}
	var claims Claims
	if err := json.Unmarshal(claimsJSON, &claims); err != nil {
		return nil, ErrInvalidToken
	}
	if time.Now().Unix() > claims.Exp {
		return nil, ErrExpiredToken
	}
	return &claims, nil
}

// sign คำนวณ HMAC-SHA256 ของ input ด้วย secret key
func sign(input string, secret []byte) []byte {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(input))
	return mac.Sum(nil)
}

// b64/unb64 เข้ารหัส/ถอดรหัส base64url แบบไม่มี padding (มาตรฐานของ JWT)
func b64(b []byte) string {
	return base64.RawURLEncoding.EncodeToString(b)
}

func unb64(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(s)
}
