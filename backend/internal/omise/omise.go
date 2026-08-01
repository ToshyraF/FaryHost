// Package omise พูดคุยกับ Omise (Opn Payments) REST API แบบเรียบง่าย โดยใช้
// แค่ net/http + encoding/json เขียนเอง (ไม่ใช้ omise-go SDK) เพื่อให้ module
// นี้ยังคงไม่มี external dependency ตามธรรมเนียมเดิมของ backend — ดู
// backend/README.md ว่าทำไม
//
// รองรับเฉพาะ PromptPay QR (flow แบบ "source" -> "charge") ซึ่งเป็นวิธีจ่าย
// เงินที่นิยมที่สุดในไทยและไม่ต้องยุ่งกับการ tokenize บัตรเครดิตฝั่ง client
package omise

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

const baseURL = "https://api.omise.co"

// สถานะของ Charge ที่ Omise ส่งกลับมา
const (
	ChargeStatusPending    = "pending"    // ยังไม่จ่าย รอลูกค้าสแกน QR
	ChargeStatusSuccessful = "successful" // จ่ายเงินสำเร็จ
	ChargeStatusFailed     = "failed"
	ChargeStatusExpired    = "expired" // QR หมดอายุก่อนลูกค้าจ่าย
)

// Client คือตัวเรียก Omise API ยืนยันตัวตนด้วย secret key ผ่าน HTTP Basic
// Auth (secret key เป็น username รหัสผ่านเว้นว่าง ตามสเปกของ Omise)
type Client struct {
	SecretKey string
	HTTP      *http.Client
}

func New(secretKey string) *Client {
	return &Client{
		SecretKey: secretKey,
		HTTP:      &http.Client{Timeout: 15 * time.Second},
	}
}

// ScannableCode คือ QR code ที่ให้ลูกค้าสแกนจ่ายเงินผ่านแอปธนาคาร
type ScannableCode struct {
	Image struct {
		DownloadURI string `json:"download_uri"`
	} `json:"image"`
}

// Source คือ "แหล่งที่มา" ของการชำระเงิน ในที่นี้คือ PromptPay QR
type Source struct {
	ID            string        `json:"id"`
	Type          string        `json:"type"`
	Amount        int64         `json:"amount"`
	Currency      string        `json:"currency"`
	ScannableCode ScannableCode `json:"scannable_code"`
}

// Charge คือรายการเรียกเก็บเงินจริง อ้างอิงกับ Source ที่สร้างไว้
// สถานะจะเปลี่ยนจาก pending เป็น successful/failed/expired เมื่อลูกค้าจ่ายเงิน
// (หรือปล่อยให้ QR หมดอายุ)
type Charge struct {
	ID       string `json:"id"`
	Status   string `json:"status"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
	Source   Source `json:"source"`
}

// CreatePromptPaySource สร้าง source แบบ PromptPay QR สำหรับยอดเงิน amount
// หน่วยเป็นสตางค์ (ตรงกับ models.Order.TotalCents พอดี ไม่ต้องแปลงหน่วย)
func (c *Client) CreatePromptPaySource(amount int64, currency string) (*Source, error) {
	form := url.Values{
		"amount":   {fmt.Sprintf("%d", amount)},
		"currency": {currency},
		"type":     {"promptpay"},
	}
	var source Source
	if err := c.post("/sources", form, &source); err != nil {
		return nil, err
	}
	return &source, nil
}

// CreateCharge เรียกเก็บเงินจาก source ที่สร้างไว้ก่อนหน้า
func (c *Client) CreateCharge(amount int64, currency, sourceID, description string) (*Charge, error) {
	form := url.Values{
		"amount":      {fmt.Sprintf("%d", amount)},
		"currency":    {currency},
		"source":      {sourceID},
		"description": {description},
	}
	var charge Charge
	if err := c.post("/charges", form, &charge); err != nil {
		return nil, err
	}
	return &charge, nil
}

// GetCharge ดึงสถานะล่าสุดของ charge ตรงจาก Omise API
//
// สำคัญ: ต้องเรียกฟังก์ชันนี้เพื่อยืนยันสถานะการจ่ายเงินเสมอ ห้ามเชื่อ
// สถานะจาก webhook payload ตรงๆ เด็ดขาด เพราะ Omise ไม่มีลายเซ็น (signature)
// มาให้ตรวจสอบว่า webhook request นั้นมาจาก Omise จริงหรือถูกปลอมขึ้นมา
// (ต่างจาก Stripe ที่มี Stripe-Signature header) — ดู handlers ที่เรียกใช้
func (c *Client) GetCharge(id string) (*Charge, error) {
	var charge Charge
	if err := c.get("/charges/"+id, &charge); err != nil {
		return nil, err
	}
	return &charge, nil
}

func (c *Client) post(path string, form url.Values, dst any) error {
	req, err := http.NewRequest(http.MethodPost, baseURL+path, bytes.NewBufferString(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	return c.do(req, dst)
}

func (c *Client) get(path string, dst any) error {
	req, err := http.NewRequest(http.MethodGet, baseURL+path, nil)
	if err != nil {
		return err
	}
	return c.do(req, dst)
}

func (c *Client) do(req *http.Request, dst any) error {
	req.SetBasicAuth(c.SecretKey, "")
	res, err := c.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("omise: request failed: %w", err)
	}
	defer res.Body.Close()

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return fmt.Errorf("omise: reading response: %w", err)
	}

	if res.StatusCode >= 400 {
		var apiErr struct {
			Message string `json:"message"`
		}
		_ = json.Unmarshal(body, &apiErr)
		if apiErr.Message == "" {
			apiErr.Message = string(body)
		}
		return fmt.Errorf("omise: %s (status %d)", apiErr.Message, res.StatusCode)
	}

	if err := json.Unmarshal(body, dst); err != nil {
		return fmt.Errorf("omise: decoding response: %w", err)
	}
	return nil
}
