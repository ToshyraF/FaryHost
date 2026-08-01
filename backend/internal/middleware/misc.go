package middleware

import (
	"log"
	"net/http"
	"time"
)

// Logging บันทึก log ของทุก request: method, path, status code, และเวลาที่ใช้
func Logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s %d %s", r.Method, r.URL.Path, rec.status, time.Since(start))
	})
}

// statusRecorder ห่อ http.ResponseWriter ไว้ เพื่อดักจับ status code ที่ handler
// เขียนออกมา (ปกติ http.ResponseWriter เฉยๆ ไม่มีทางอ่านค่านี้กลับมาได้)
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

// CORS อนุญาตให้ Flutter app (ที่รันคนละ origin ตอน dev เช่น flutter run -d chrome)
// เรียก API นี้ได้
func CORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			// เบราว์เซอร์ยิง OPTIONS มาถามก่อน (preflight) ตอบ 204 ว่างๆ กลับไปพอ
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
