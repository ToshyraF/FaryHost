// Package authutil implements password hashing and JWT issuing/verification
// using only the standard library (crypto/hmac, crypto/sha256), since this
// module intentionally has no external dependencies — see backend/README.md.
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
	pbkdf2Iterations = 100_000
	saltLen          = 16
	keyLen           = 32
)

// HashPassword derives a salted PBKDF2-HMAC-SHA256 hash and encodes it as
// "pbkdf2$iterations$saltB64$hashB64".
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

// VerifyPassword checks a plaintext password against an encoded hash
// produced by HashPassword.
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
	return hmac.Equal(got, want)
}

// pbkdf2 implements RFC 8018 PBKDF2 with HMAC-SHA256, hand-rolled to avoid
// pulling in golang.org/x/crypto/pbkdf2.
func pbkdf2(password string, salt []byte, iterations, keyLen int) []byte {
	hashLen := sha256.Size
	numBlocks := (keyLen + hashLen - 1) / hashLen

	out := make([]byte, 0, numBlocks*hashLen)
	for block := 1; block <= numBlocks; block++ {
		out = append(out, pbkdf2Block(password, salt, iterations, block)...)
	}
	return out[:keyLen]
}

func pbkdf2Block(password string, salt []byte, iterations, blockIndex int) []byte {
	mac := hmac.New(sha256.New, []byte(password))

	blockNum := make([]byte, 4)
	binary.BigEndian.PutUint32(blockNum, uint32(blockIndex))
	mac.Write(salt)
	mac.Write(blockNum)
	u := mac.Sum(nil)

	result := make([]byte, len(u))
	copy(result, u)

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
