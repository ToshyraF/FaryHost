package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/ToshyraF/FaryHost/backend/internal/authutil"
	"github.com/ToshyraF/FaryHost/backend/internal/httpjson"
)

type contextKey string

const claimsContextKey contextKey = "claims"

// RequireAuth คือ middleware ที่ตรวจสอบ Bearer token ใน header Authorization
// ถ้าถูกต้อง จะแนบ claims (user ID + role) ไปกับ request context เพื่อให้
// handler ตัวถัดไปเรียก ClaimsFromContext มาใช้ได้
func RequireAuth(secret []byte) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			token, ok := strings.CutPrefix(header, "Bearer ")
			if !ok || token == "" {
				httpjson.Error(w, http.StatusUnauthorized, "missing bearer token")
				return
			}

			claims, err := authutil.ParseToken(token, secret)
			if err != nil {
				httpjson.Error(w, http.StatusUnauthorized, "invalid or expired token")
				return
			}

			ctx := context.WithValue(r.Context(), claimsContextKey, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireRole ปฏิเสธ request ที่ผู้ใช้ที่ login อยู่ไม่ใช่ role ที่กำหนด
// ต้องนำไปต่อ "หลัง" RequireAuth เสมอ (ต้องมี claims อยู่ใน context ก่อนแล้ว)
func RequireRole(role string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, ok := ClaimsFromContext(r.Context())
			if !ok || claims.Role != role {
				httpjson.Error(w, http.StatusForbidden, "requires "+role+" role")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// ClaimsFromContext ดึง claims ที่ RequireAuth แนบไว้ใน context กลับมาใช้ใน handler
func ClaimsFromContext(ctx context.Context) (*authutil.Claims, bool) {
	claims, ok := ctx.Value(claimsContextKey).(*authutil.Claims)
	return claims, ok
}
