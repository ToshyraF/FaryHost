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

// authResponse คือรูปแบบ response ที่ทั้ง Register และ Login คืนกลับ: token
// สำหรับใช้เรียก API อื่นๆ ต่อ พร้อมข้อมูลผู้ใช้
type authResponse struct {
	Token string      `json:"token"`
	User  models.User `json:"user"`
}

// Register สมัครสมาชิกใหม่ (role ต้องเป็น "customer" หรือ "vendor" เท่านั้น)
// แล้วออก JWT ให้เลยทันที (ไม่ต้อง login ซ้ำหลังสมัคร)
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

// Login ตรวจสอบอีเมล/รหัสผ่าน แล้วออก JWT ใหม่ให้ถ้าถูกต้อง
func (s *Server) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := httpjson.Decode(r, &req); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "invalid request body")
		return
	}

	email := strings.ToLower(strings.TrimSpace(req.Email))
	user, err := s.Store.GetUserByEmail(email)
	if err != nil || !authutil.VerifyPassword(user.PasswordHash, req.Password) {
		// จงใจตอบข้อความเดียวกันไม่ว่าจะเป็นเพราะ "ไม่มีอีเมลนี้" หรือ "รหัสผ่านผิด"
		// เพื่อไม่ให้คนร้ายรู้ว่าอีเมลไหนมีอยู่ในระบบจริง
		httpjson.Error(w, http.StatusUnauthorized, "invalid email or password")
		return
	}

	s.respondWithToken(w, user)
}

// respondWithToken ออก JWT ให้ user แล้วส่ง response กลับในรูปแบบเดียวกันทั้ง
// Register และ Login
func (s *Server) respondWithToken(w http.ResponseWriter, user *models.User) {
	token, err := authutil.GenerateToken(user.ID, string(user.Role), s.Config.JWTSecret, s.Config.TokenTTL)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "could not issue token")
		return
	}
	httpjson.Write(w, http.StatusOK, authResponse{Token: token, User: *user})
}
