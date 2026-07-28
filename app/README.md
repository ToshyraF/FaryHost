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

Or run `scripts/run_dev.sh` from the repo root — it starts the backend,
runs `flutter create .` if the platform folders don't exist yet, then
`flutter pub get` and `flutter run` (pass device flags through, e.g.
`scripts/run_dev.sh -d chrome`). Requires Go and Flutter/Dart installed
locally; neither is available in the sandbox this was written in, so this
script has not actually been run — see "Status" below.

## Pointing at the backend

`ApiClient` (`lib/core/api_client.dart`) defaults to
`http://localhost:8080/api`. Override per platform:

- Android emulator: `ApiClient(baseUrl: 'http://10.0.2.2:8080/api')` — `localhost` inside the emulator is the emulator itself, not your machine.
- iOS simulator / desktop / web: the default `localhost` is correct.
- Physical device: use your machine's LAN IP.

## Layout

- `lib/core/models` — plain Dart classes mirroring the backend's JSON (`User`, `Vendor`, `MenuItem`, `Order`). Keep `OrderStatus` in `lib/core/models/order.dart` in sync with `backend/internal/models/models.go` if the status machine changes.
- `lib/core/api_client.dart` — the only place that talks HTTP; every screen goes through it. Takes an optional `client: http.Client` so tests can swap in `package:http/testing.dart`'s `MockClient` instead of hitting the network.
- `lib/core/state` — `AuthState` (session + token persistence via `shared_preferences`) and `CartState` (single-vendor cart, since an order belongs to one stall) as `ChangeNotifier`s via `provider`.
- `lib/features/auth` — login/register.
- `lib/features/customer` — stall list, stall menu + add to cart, cart/checkout, order status (polls every 5s while open), order history.
- `lib/features/vendor` — stall setup, orders tab (accept/prepare/ready/complete, polls every 8s), menu management tab.

## Golden tests

`test/golden/` has widget-level golden (screenshot) tests for the screens
that render meaningfully without a live backend: login, register, cart
(empty + with items), the vendor list, order status, and the vendor
create-stall form. Screens that need data mock the network via
`package:http/testing.dart`'s `MockClient` (see
`vendor_list_screen_test.dart`, `order_status_screen_test.dart`,
`vendor_create_stall_screen_test.dart` for the pattern) — `test_helpers.dart`'s
`pumpGolden` wires up the same providers `main.dart` does.

```
flutter test                      # run all tests, compares against test/golden/*/goldens/*.png
flutter test --update-goldens     # (re)generate the reference PNGs after an intentional UI change
```

**The reference PNGs are not included yet.** `matchesGoldenFile` needs a
real Flutter renderer to produce them, and this sandbox has neither the
Flutter SDK nor network access to install it (see "Status" below) — so
`flutter test --update-goldens` has never actually been run for this repo.
Run it once on a machine with Flutter installed, eyeball the generated
`test/golden/*/goldens/*.png` files to confirm they look right, then commit
them — after that, plain `flutter test` will catch any unintended visual
regression. Golden images are OS/Flutter-version sensitive; regenerate them
if you change Flutter version or run CI on a different OS than local dev.

**Don't have Flutter locally either?** `.github/workflows/ci.yml`'s `flutter`
job runs `flutter test` on every push/PR. Since no golden PNGs are committed
yet, that step is *expected to fail* the first time — but `flutter_test`
automatically renders the actual output of every failing/missing golden
comparison into a `failures/` folder next to the test, and the workflow
uploads that folder as the `golden-test-failures` artifact regardless of
pass/fail. Download it from the workflow run's Summary page, eyeball the
rendered screenshots, and if they look right, either copy them into
`test/golden/*/goldens/` yourself or run `flutter test --update-goldens`
locally once you have Flutter — then commit. Don't treat this failure as a
bug to silence (e.g. by making the step `continue-on-error`); a real
regression later needs this check to still be able to go red.

## Status

Written and reviewed for consistency against the backend's request/response
shapes, but this environment has no Flutter/Dart SDK — and its network
policy blocks both the SDK download host (`storage.googleapis.com`) and
`pub.dev` — so `flutter analyze`, `flutter run`, and `flutter test`
(including generating the golden tests' reference images) have not actually
been run against this code. Treat it as unverified until you run it locally
with `scripts/run_dev.sh` or the manual steps above.
