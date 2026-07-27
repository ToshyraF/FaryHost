# FaryHost app

Flutter client for the market pre-order/pickup app. One app, two role-based
homes after login: customers browse stalls and order ahead; vendors manage
their stall's menu and incoming orders. Talks to the API in `backend/`.

## First-time setup

This scaffold has `pubspec.yaml` and `lib/` only — the platform runner
folders (`android/`, `ios/`, `web/`, ...) aren't included because they're
generated tooling output, not something to hand-write or review as source.
Generate them once with Flutter installed:

```
cd app
flutter create . --project-name faryhost_app   # adds android/, ios/, web/, etc. without touching lib/
flutter pub get
flutter run
```

## Pointing at the backend

`ApiClient` (`lib/core/api_client.dart`) defaults to
`http://localhost:8080/api`. Override per platform:

- Android emulator: `ApiClient(baseUrl: 'http://10.0.2.2:8080/api')` — `localhost` inside the emulator is the emulator itself, not your machine.
- iOS simulator / desktop / web: the default `localhost` is correct.
- Physical device: use your machine's LAN IP.

## Layout

- `lib/core/models` — plain Dart classes mirroring the backend's JSON (`User`, `Vendor`, `MenuItem`, `Order`). Keep `OrderStatus` in `lib/core/models/order.dart` in sync with `backend/internal/models/models.go` if the status machine changes.
- `lib/core/api_client.dart` — the only place that talks HTTP; every screen goes through it.
- `lib/core/state` — `AuthState` (session + token persistence via `shared_preferences`) and `CartState` (single-vendor cart, since an order belongs to one stall) as `ChangeNotifier`s via `provider`.
- `lib/features/auth` — login/register.
- `lib/features/customer` — stall list, stall menu + add to cart, cart/checkout, order status (polls every 5s while open), order history.
- `lib/features/vendor` — stall setup, orders tab (accept/prepare/ready/complete, polls every 8s), menu management tab.

## Status

Written and reviewed for consistency against the backend's request/response
shapes, but this environment has no Flutter/Dart SDK, so `flutter analyze`
and `flutter run` have not actually been run against this code. Treat it as
unverified until you run it locally.
