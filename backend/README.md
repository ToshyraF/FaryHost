# FaryHost backend

Go API for the market pre-order/pickup app: vendors set up a stall and menu,
customers browse stalls and place pre-orders, vendors move each order through
`pending -> accepted -> preparing -> ready -> completed` (or `cancelled`),
and the customer shows their pickup code at the stall.

## Running

```
make run     # starts the API on :8080 (override with ADDR=:PORT)
make test
make vet
make fmt
```

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
| POST | `/api/orders` | customer | places a pre-order |
| GET | `/api/orders/me` | customer | order history |
| GET | `/api/orders/{id}` | customer or owning vendor | |
| GET | `/api/vendors/me/orders` | vendor | incoming orders |
| PATCH | `/api/orders/{id}/status` | vendor | must follow `NextStatuses` |
