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

// RequireAuth verifies the Bearer token and attaches its claims to the
// request context. Handlers read them back with ClaimsFromContext.
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

// RequireRole rejects requests whose authenticated user isn't one of the
// given roles. Must be mounted after RequireAuth.
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

func ClaimsFromContext(ctx context.Context) (*authutil.Claims, bool) {
	claims, ok := ctx.Value(claimsContextKey).(*authutil.Claims)
	return claims, ok
}
