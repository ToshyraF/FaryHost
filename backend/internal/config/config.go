package config

import (
	"os"
	"time"
)

// Config holds runtime configuration loaded from environment variables.
type Config struct {
	Addr      string
	JWTSecret []byte
	TokenTTL  time.Duration
}

func Load() Config {
	return Config{
		Addr:      getEnv("ADDR", ":8080"),
		JWTSecret: []byte(getEnv("JWT_SECRET", "dev-secret-change-me")),
		TokenTTL:  24 * time.Hour,
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
