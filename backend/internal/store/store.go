// Package store เก็บข้อมูลทั้งหมดไว้ในหน่วยความจำ (in-memory) ผ่าน API
// รูปแบบ repository เล็กๆ ดู backend/README.md ว่าทำไม: sandbox นี้ network
// policy บล็อก Go module proxy เลยดึง driver จริง (pgx/lib/pq) มาใช้ไม่ได้
// method ทุกตัวด้านล่างถูกออกแบบ signature ไว้ให้ implementation ที่ต่อกับ
// Postgres จริงมาแทนได้ทีหลัง โดยไม่ต้องแก้โค้ดฝั่ง handlers เลย
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
	ErrConflict = errors.New("conflict") // เช่น อีเมลซ้ำ หรือร้านค้าที่มีอยู่แล้ว
)

// Store คือฐานข้อมูลจำลองในหน่วยความจำ ข้อมูลจะหายทั้งหมดเมื่อ process รีสตาร์ท
// ใช้ sync.RWMutex (mu) ล็อกป้องกัน race condition เวลามีหลาย request เข้ามาพร้อมกัน
type Store struct {
	mu sync.RWMutex

	usersByID    map[string]*models.User
	usersByEmail map[string]string // email -> user ID (ใช้หา user ตอน login)

	vendorsByID     map[string]*models.Vendor
	vendorByOwnerID map[string]string // owner user ID -> vendor ID (เช็คว่า 1 คนเปิดร้านได้แค่ 1 ร้าน)

	menuItemsByID map[string]*models.MenuItem

	ordersByID map[string]*models.Order
}

// New สร้าง Store เปล่าๆ พร้อมใช้งาน (ต้องเรียกก่อนใช้งานเสมอ ห้ามใช้ Store{} ตรงๆ
// เพราะ map ข้างในยังไม่ได้ถูก make)
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

// CreateUser สร้างผู้ใช้ใหม่ คืน ErrConflict ถ้าอีเมลนี้มีคนใช้แล้ว
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

// CreateVendor สร้างร้านค้าใหม่ คืน ErrConflict ถ้า user คนนี้เปิดร้านไปแล้ว
// (กติกา: 1 vendor user เปิดร้านได้แค่ 1 ร้านเท่านั้น)
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

// GetVendorByOwnerID ใช้หาร้านค้าของ vendor user ที่ login อยู่ (endpoint /vendors/me)
func (s *Store) GetVendorByOwnerID(ownerUserID string) (*models.Vendor, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	id, ok := s.vendorByOwnerID[ownerUserID]
	if !ok {
		return nil, ErrNotFound
	}
	return s.vendorsByID[id], nil
}

// ListVendors คืนร้านค้าทั้งหมด เรียงตามวันที่สร้างก่อนหลัง (ร้านเก่าสุดขึ้นก่อน)
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

// ListMenuItemsByVendor คืนเมนูทั้งหมดของร้านค้าหนึ่งร้าน (รวมเมนูที่หมด/ปิดขายด้วย
// เพราะ handler ฝั่งร้านค้าต้องเห็นครบเพื่อจัดการเมนู ส่วนฝั่งลูกค้าจะกรองเองที่ UI)
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

// CreateOrder บันทึกออเดอร์ใหม่ พร้อมสุ่มรหัสรับอาหาร (Code) ให้อัตโนมัติ
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

// ListOrdersByCustomer คืนประวัติการสั่งของลูกค้าคนหนึ่ง (ใหม่สุดขึ้นก่อน)
func (s *Store) ListOrdersByCustomer(customerID string) []*models.Order {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.filterOrdersLocked(func(o *models.Order) bool { return o.CustomerID == customerID })
}

// ListOrdersByVendor คืนออเดอร์ที่เข้ามาที่ร้านค้าหนึ่งร้าน (ใหม่สุดขึ้นก่อน)
func (s *Store) ListOrdersByVendor(vendorID string) []*models.Order {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.filterOrdersLocked(func(o *models.Order) bool { return o.VendorID == vendorID })
}

// filterOrdersLocked จะถูกเรียกตอนที่ mu ถูกล็อกไว้แล้วเท่านั้น (จะ read lock หรือ
// write lock ก็ได้ ฟังก์ชันนี้แค่วนอ่าน ไม่ได้แก้ไขอะไร)
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

// UpdateOrderStatus เปลี่ยนสถานะออเดอร์และอัปเดตเวลาแก้ไขล่าสุด
// (การเช็คว่าเปลี่ยนสถานะข้ามขั้นได้หรือไม่ ทำที่ชั้น handlers ไม่ใช่ที่นี่)
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
