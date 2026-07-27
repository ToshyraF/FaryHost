package handlers

import (
	"errors"
	"net/http"
	"strings"

	"github.com/ToshyraF/FaryHost/backend/internal/authutil"
	"github.com/ToshyraF/FaryHost/backend/internal/httpjson"
	"github.com/ToshyraF/FaryHost/backend/internal/models"
	"github.com/ToshyraF/FaryHost/backend/internal/store"
)

type registerRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	FullName string `json:"full_name"`
	Phone    string `json:"phone"`
	Role     string `json:"role"`
}

type authResponse struct {
	Token string      `json:"token"`
	User  models.User `json:"user"`
}

func (s *Server) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.Email == "" || len(req.Password) < 8 || req.FullName == "" {
		httpjson.Error(w, http.StatusBadRequest, "email, full_name, and a password of at least 8 characters are required")
		return
	}

	role := models.Role(req.Role)
	if role != models.RoleCustomer && role != models.RoleVendor {
		httpjson.Error(w, http.StatusBadRequest, "role must be \"customer\" or \"vendor\"")
		return
	}

	hash, err := authutil.HashPassword(req.Password)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not process password")
		return
	}

	user := &models.User{
		Email:        req.Email,
		PasswordHash: hash,
		FullName:     req.FullName,
		Phone:        req.Phone,
		Role:         role,
	}
	if err := s.Store.CreateUser(user); err != nil {
		if errors.Is(err, store.ErrConflict) {
			httpjson.Error(w, http.StatusConflict, "an account with this email already exists")
			return
		}
		httpjson.Error(w, http.StatusInternalServerError, "could not create account")
		return
	}

	s.respondWithToken(w, user)
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (s *Server) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}

	email := strings.ToLower(strings.TrimSpace(req.Email))
	user, err := s.Store.GetUserByEmail(email)
	if err != nil || !authutil.VerifyPassword(user.PasswordHash, req.Password) {
		httpjson.Error(w, http.StatusUnauthorized, "invalid email or password")
		return
	}

	s.respondWithToken(w, user)
}

func (s *Server) respondWithToken(w http.ResponseWriter, user *models.User) {
	token, err := authutil.GenerateToken(user.ID, string(user.Role), s.Config.JWTSecret, s.Config.TokenTTL)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not issue token")
		return
	}
	httpjson.Write(w, http.StatusOK, authResponse{Token: token, User: *user})
}
