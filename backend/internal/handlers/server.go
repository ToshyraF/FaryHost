// Package handlers implements the HTTP API: request parsing, validation,
// and translating store results into JSON responses.
package handlers

import (
	"github.com/ToshyraF/FaryHost/backend/internal/config"
	"github.com/ToshyraF/FaryHost/backend/internal/store"
)

type Server struct {
	Store  *store.Store
	Config config.Config
}

func New(s *store.Store, cfg config.Config) *Server {
	return &Server{Store: s, Config: cfg}
}
