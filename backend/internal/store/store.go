// Package store holds application state in memory behind a small
// repository-style API. See backend/README.md for why: this sandbox's
// network policy blocks the Go module proxy, so a real driver
// (pgx/lib/pq) can't be fetched here. Every method signature below is
// written so a Postgres-backed implementation can be swapped in later
// without touching handlers.
package store

import (
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/ToshyraF/FaryHost/backend/internal/idgen"
	"github.com/ToshyraF/FaryHost/backend/internal/models"
)

var (
	ErrNotFound = errors.New("not found")
	ErrConflict = errors.New("conflict")
)

type Store struct {
	mu sync.RWMutex

	usersByID    map[string]*models.User
	usersByEmail map[string]string // email -> user ID

	vendorsByID     map[string]*models.Vendor
	vendorByOwnerID map[string]string // owner user ID -> vendor ID

	menuItemsByID map[string]*models.MenuItem

	ordersByID map[string]*models.Order
}

func New() *Store {
	return &Store{
		usersByID:       make(map[string]*models.User),
		usersByEmail:    make(map[string]string),
		vendorsByID:     make(map[string]*models.Vendor),
		vendorByOwnerID: make(map[string]string),
		menuItemsByID:   make(map[string]*models.MenuItem),
		ordersByID:      make(map[string]*models.Order),
	}
}

// --- Users ---

func (s *Store) CreateUser(u *models.User) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.usersByEmail[u.Email]; exists {
		return ErrConflict
	}
	u.ID = idgen.UUID()
	u.CreatedAt = time.Now().UTC()
	s.usersByID[u.ID] = u
	s.usersByEmail[u.Email] = u.ID
	return nil
}

func (s *Store) GetUserByEmail(email string) (*models.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	id, ok := s.usersByEmail[email]
	if !ok {
		return nil, ErrNotFound
	}
	return s.usersByID[id], nil
}

func (s *Store) GetUserByID(id string) (*models.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	u, ok := s.usersByID[id]
	if !ok {
		return nil, ErrNotFound
	}
	return u, nil
}

// --- Vendors ---

func (s *Store) CreateVendor(v *models.Vendor) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.vendorByOwnerID[v.OwnerUserID]; exists {
		return ErrConflict
	}
	v.ID = idgen.UUID()
	v.CreatedAt = time.Now().UTC()
	s.vendorsByID[v.ID] = v
	s.vendorByOwnerID[v.OwnerUserID] = v.ID
	return nil
}

func (s *Store) GetVendorByID(id string) (*models.Vendor, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	v, ok := s.vendorsByID[id]
	if !ok {
		return nil, ErrNotFound
	}
	return v, nil
}

func (s *Store) GetVendorByOwnerID(ownerUserID string) (*models.Vendor, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	id, ok := s.vendorByOwnerID[ownerUserID]
	if !ok {
		return nil, ErrNotFound
	}
	return s.vendorsByID[id], nil
}

func (s *Store) ListVendors() []*models.Vendor {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]*models.Vendor, 0, len(s.vendorsByID))
	for _, v := range s.vendorsByID {
		out = append(out, v)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
	return out
}

func (s *Store) UpdateVendor(v *models.Vendor) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.vendorsByID[v.ID]; !ok {
		return ErrNotFound
	}
	s.vendorsByID[v.ID] = v
	return nil
}

// --- Menu items ---

func (s *Store) CreateMenuItem(item *models.MenuItem) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	item.ID = idgen.UUID()
	item.CreatedAt = time.Now().UTC()
	s.menuItemsByID[item.ID] = item
	return nil
}

func (s *Store) GetMenuItem(id string) (*models.MenuItem, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	item, ok := s.menuItemsByID[id]
	if !ok {
		return nil, ErrNotFound
	}
	return item, nil
}

func (s *Store) ListMenuItemsByVendor(vendorID string) []*models.MenuItem {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]*models.MenuItem, 0)
	for _, item := range s.menuItemsByID {
		if item.VendorID == vendorID {
			out = append(out, item)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
	return out
}

func (s *Store) UpdateMenuItem(item *models.MenuItem) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.menuItemsByID[item.ID]; !ok {
		return ErrNotFound
	}
	s.menuItemsByID[item.ID] = item
	return nil
}

func (s *Store) DeleteMenuItem(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.menuItemsByID[id]; !ok {
		return ErrNotFound
	}
	delete(s.menuItemsByID, id)
	return nil
}

// --- Orders ---

func (s *Store) CreateOrder(o *models.Order) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	o.ID = idgen.UUID()
	o.Code = idgen.PickupCode()
	now := time.Now().UTC()
	o.CreatedAt = now
	o.UpdatedAt = now
	s.ordersByID[o.ID] = o
	return nil
}

func (s *Store) GetOrder(id string) (*models.Order, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	o, ok := s.ordersByID[id]
	if !ok {
		return nil, ErrNotFound
	}
	return o, nil
}

func (s *Store) ListOrdersByCustomer(customerID string) []*models.Order {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.filterOrdersLocked(func(o *models.Order) bool { return o.CustomerID == customerID })
}

func (s *Store) ListOrdersByVendor(vendorID string) []*models.Order {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.filterOrdersLocked(func(o *models.Order) bool { return o.VendorID == vendorID })
}

// filterOrdersLocked assumes the caller already holds s.mu (read or write).
func (s *Store) filterOrdersLocked(match func(*models.Order) bool) []*models.Order {
	out := make([]*models.Order, 0)
	for _, o := range s.ordersByID {
		if match(o) {
			out = append(out, o)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out
}

func (s *Store) UpdateOrderStatus(id string, status models.OrderStatus) (*models.Order, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	o, ok := s.ordersByID[id]
	if !ok {
		return nil, ErrNotFound
	}
	o.Status = status
	o.UpdatedAt = time.Now().UTC()
	return o, nil
}
