# FaryHost backend

Go API for the market pre-order/pickup app: vendors set up a stall and menu,
customers browse stalls and place pre-orders. Payment is mandatory and
upfront via Omise (Opn Payments) PromptPay QR — an order starts at
`awaiting_payment` and only becomes visible/actionable for the vendor once
payment clears, then moves through `pending -> accepted -> preparing ->
ready -> completed` (or `cancelled`), and the customer shows their pickup
code at the stall.

## Running

```
make run     # starts the API on :8080 (override with ADDR=:PORT)
make test
make vet
make fmt
```

## Payments (Omise / Opn Payments)

Set `OMISE_SECRET_KEY` before running, or every order will fail to create
(502 — Omise rejects requests signed with an empty key). Get a test-mode
secret key instantly at [Opn Payments](https://opn.ooo) — no approval wait,
sandbox keys work immediately. `PAYMENT_CURRENCY` defaults to `thb`.

```
OMISE_SECRET_KEY=skey_test_xxxxxxxxxxxx make run
```

Flow: `CreateOrder` creates a PromptPay source + charge with Omise *before*
persisting the order — if that fails, nothing is saved (no half-created
orders sitting around). The order carries the charge's QR code URL back to
the client and starts life at `awaiting_payment`.

Two paths confirm payment and flip the order to `pending`, both funneling
through `handlers.confirmPayment`:
- **`POST /api/webhooks/omise`** — register this URL in the Omise dashboard for the fast path. Public endpoint, no JWT.
- **`GET /api/orders/{id}`** — as a fallback/for local dev, since a public webhook URL usually isn't available there. Every time this is called on an order still `awaiting_payment`, the handler re-checks with Omise itself.

**Security note:** unlike Stripe's `Stripe-Signature` header, Omise webhooks
carry no signature to verify the sender. `confirmPayment` never trusts the
webhook body's status — it only uses the payload to find *which* charge to
re-check, then calls `GET /charges/{id}` on Omise's API directly (which
does require the secret key) and trusts only that response.

This has **not been tested against the real Omise API** — this sandbox has
no network access to `api.omise.co` (see the network-policy note above).
The integration was verified as far as this environment allows: the
handler builds, and a local run confirmed `CreateOrder` fails cleanly
(502, nothing persisted) when Omise is unreachable, and the webhook
endpoint validates payload shape correctly. End-to-end payment (a real
charge actually going from `pending` to `successful`) needs testing
somewhere with real network access and a real Omise test key.

## No external dependencies, on purpose

`go.mod` has zero `require` entries. This isn't a style choice — the sandbox
this was built in blocks egress to `proxy.golang.org`, so `go get` can't fetch
anything. To make that a non-issue rather than a blocker:

- **Routing**: `net/http`'s `ServeMux` (Go 1.22+ method+path patterns), no chi/gorilla.
- **Auth**: hand-rolled HS256 JWT and PBKDF2-HMAC-SHA256 password hashing in
  `internal/authutil`, instead of `golang-jwt/jwt` and `x/crypto/bcrypt`.
- **IDs**: `internal/idgen` builds UUIDv4 and short pickup codes from
  `crypto/rand` directly, instead of `google/uuid`.
- **Persistence**: `internal/store` is an in-memory, mutex-guarded store
  instead of Postgres (no driver like `pgx`/`lib/pq` could be fetched
  either). Every method is defined on a narrow `*Store` type with the same
  shape a DB-backed implementation would have, so swapping in Postgres later
  means writing a new `internal/store` implementation, not touching
  `internal/handlers`. Data does not survive a process restart in the
  meantime.

If your environment can reach the module proxy, swapping any of the above
for a "real" library is a localized change — nothing outside that package
needs to know.

## Layout

- `cmd/api` — process entrypoint, route wiring, middleware chain.
- `internal/models` — domain types (`User`, `Vendor`, `MenuItem`, `Order`, `OrderItem`) and the order status state machine (`NextStatuses`).
- `internal/store` — in-memory persistence (see above).
- `internal/omise` — hand-rolled REST client for Omise (source, charge, get-charge) — see "Payments" above.
- `internal/handlers` — HTTP handlers, one file per resource.
- `internal/middleware` — JWT auth, role gating, logging, CORS.
- `internal/authutil`, `internal/idgen`, `internal/httpjson`, `internal/config` — small stdlib-only support packages.

## API summary

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/api/auth/register` | – | `role` must be `customer` or `vendor` |
| POST | `/api/auth/login` | – | |
| GET | `/api/vendors` | – | public stall list |
| GET | `/api/vendors/{id}` | – | public stall detail + menu |
| POST/GET/PATCH | `/api/vendors/me` | vendor | one stall per vendor user |
| POST/GET | `/api/vendors/me/menu-items` | vendor | |
| PATCH/DELETE | `/api/vendors/me/menu-items/{id}` | vendor | |
| POST | `/api/orders` | customer | places a pre-order; creates an Omise PromptPay charge, starts at `awaiting_payment` |
| GET | `/api/orders/me` | customer | order history |
| GET | `/api/orders/{id}` | customer or owning vendor | also re-checks payment status with Omise if still `awaiting_payment` |
| GET | `/api/vendors/me/orders` | vendor | incoming orders |
| PATCH | `/api/orders/{id}/status` | vendor | must follow `NextStatuses`; can't move `awaiting_payment` -> `pending` (system-only) |
| POST | `/api/webhooks/omise` | – | Omise calls this; re-verifies with Omise before trusting anything |
