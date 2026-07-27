// Package idgen generates IDs using only the standard library, since this
// module has no external dependencies (see backend/README.md).
package idgen

import (
	"crypto/rand"
	"fmt"
)

// UUID returns a random UUIDv4 string.
func UUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant 10
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

const pickupCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no 0/O/1/I

// PickupCode returns a short, human-friendly code customers show at the
// stall to collect their order (e.g. "K7X4Q9").
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
