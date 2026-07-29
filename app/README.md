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
- `lib/features/auth` — welcome (shown first, before login) / login / register.
- `lib/features/customer` — market map (customer home, see below) / stall list (alternate view), stall menu + add to cart, cart/checkout (payment is mandatory — `CreateOrder` always comes back `awaiting_payment`), order status (shows a PromptPay QR while `awaiting_payment`, switches to the pickup code once paid; polls every 5s, which doubles as the payment-status check), order history.
- `lib/features/vendor` — stall setup, orders tab (accept/prepare/ready/complete, polls every 8s), menu management tab.

## Market map

`MarketMapScreen` is the customer home (`AuthGate` routes here, not straight
to the plain list — that's still reachable via the app bar's "ดูแบบรายการ"
button). Stalls are laid out in a fixed grid derived from their index in the
vendor list (deterministic, not random, so the map looks the same on every
load); tapping empty ground walks an avatar there via `AnimatedPositioned`,
tapping a stall walks the avatar to it and opens that stall's menu, and a
stall's marker scales up slightly and its border highlights when the avatar
is within `_nearRadius`. Walking close enough to a stall (without tapping it
directly) auto-opens that stall's menu too — `_maybeAutoOpenNearbyVendor`,
called after every ground tap, edge-triggers on entering `_nearRadius` (once
per approach, tracked via `_lastNearVendorId`, not every frame the avatar
stays there) so standing near a stall doesn't repeatedly push the menu
screen. Every stall still stays tappable regardless of avatar position too
(no functional gate), since this is a real ordering app first.

The map floor and everything on it is built from plain widgets — a
`CustomPainter` for the ground, `Icon`/`Container`/`DecoratedBox` for the
avatar and stall markers — rather than an illustrated background or a game
engine. Two reasons: this sandbox has no network access to fetch any image
assets, and adding an untested new package (on top of everything else
that's never been run — see "Status") wasn't worth the risk for what a
`CustomPainter` can already do for the default experience.

The avatar (`_Avatar` in `market_map_screen.dart`) is a small pixel-art RPG
sprite (red cap, face, blue jacket, dark pants, black shoes) in the style of
classic top-down Pokémon-like overworld characters, per a reference
screenshot the user shared. It's drawn entirely by `_PixelSpritePainter`, a
`CustomPainter` that fills one small `Rect` per character in the
`_spriteRows` string grid (each row a line of the sprite, each character a
palette key into `_spriteColors`, `.` meaning transparent) — no image
assets, same constraint as everywhere else in this app; a hand-authored
pixel grid sidesteps needing to fetch a real sprite sheet. The grid/palette
were designed and checked by rendering the same grid as an HTML `<canvas>`
and screenshotting it with the pre-installed headless Chromium before ever
touching the Dart code — the same verification technique used to catch and
fix the previous shape-based avatar's `Align` bug (kept only as
`_avatarWidth`/`_avatarHeight`, now derived from the grid's own dimensions
via `_spriteRows.first.length`/`_spriteRows.length` rather than hardcoded,
so the on-screen size can never drift out of sync with the grid).

### Experimental: Flame version

`lib/features/customer/market_game/` is the same map re-implemented on top
of [Flame](https://flame-engine.org) (`MarketFlameGame` + `FlameGame`
components for the ground, player, and stalls), reachable from
`MarketMapScreen`'s app bar ("ทดลองเวอร์ชันเกม") rather than replacing the
default screen. This is a genuine, first-time experiment: `flame` is the
first external package added to this app since the widget-only approach
above was chosen specifically to avoid this risk, and — like everything
else here — it has never been built, since this sandbox has no network
access to `pub.dev` to fetch it or a Flutter SDK to compile it. Expect it
to need a round or two of CI-driven fixes (see `.github/workflows/ci.yml`)
before it actually renders correctly; that's the plan, not a sign
something's wrong. It deliberately doesn't replace `MarketMapScreen` so the
app keeps a working customer experience regardless of how that shakes out.
The camera follows the player vertically and is clamped to the map's
extent (`camera.follow(player, verticalOnly: true)` in `onLoad`, plus a
manual clamp of `camera.viewfinder.position.y` in `update()` — not
`camera.setBounds`, whose bounds-shape API/import didn't match the Flame
version CI resolves) in `market_flame_game.dart`, so a map taller than the
viewport (more vendors than fit on screen at once) scrolls as the player
walks toward the bottom rows instead of clipping — no horizontal follow
since the grid's fixed column count always fits the screen width exactly.
Same proximity auto-open as the widget version: each `StallComponent` has a
`wasNear` flag, checked every `update()` tick against `_nearRadius`, so
walking close opens that stall's menu once per approach; tapping a stall
directly sets `wasNear = true` immediately so the walk-in animation landing
on the stall doesn't also fire the proximity trigger right after.
`PlayerComponent` gets the same pixel-art sprite as the widget version's
`_Avatar` — the exact same `_spriteRows`/`_spriteColors` grid, copied
rather than shared via import so this experimental version stays free-
standing — drawn by overriding `render(Canvas canvas)` directly and calling
`canvas.drawRect` per pixel, instead of composing `CircleComponent`/
`RectangleComponent` children like the previous shape-based look did.
`render(Canvas)` is the same core hook every built-in Flame shape component
already implements internally, so this is, if anything, less exposed to
unverified Flame API surface than the child-component approach was.

## Payment

Payment is mandatory and happens before the vendor ever sees the order —
there's no cash-on-pickup option. `CreateOrder` always returns an order at
`OrderStatus.awaitingPayment` with `paymentQRCodeUri` set to a PromptPay QR
code image (from the backend's Omise integration — see
`backend/README.md`'s Payments section for the full flow and the security
note on why webhook payloads are never trusted directly).
`OrderStatusScreen` shows that QR and keeps polling every 5s; once the
backend confirms payment with Omise, the same poll picks up the status
flip to `pending` and switches to the normal pickup-code view.

## Font

Almost all UI text is Thai, so the app bundles `Loma` (`assets/fonts/`, from
the fonts-tlwg project — see `assets/fonts/LICENSE-Loma.txt`) and sets it as
the app-wide default via `lib/core/theme.dart`'s `buildAppTheme()`, rather
than relying on whatever Thai fallback font each platform happens to ship.
`test/flutter_test_config.dart` loads the same font before any test runs,
and `test_helpers.dart`'s `pumpGolden` uses the same `buildAppTheme()` as
`main.dart` (a shared function, not two copies, so they can't drift apart)
— both matter because the `flutter_tester` test environment has no real
fonts at all unless the app explicitly loads one, so without this every
golden screenshot would show blank boxes instead of the actual Thai text.

## Golden tests

`test/golden/` has widget-level golden (screenshot) tests for the screens
that render meaningfully without a live backend: welcome, login, register,
cart (empty + with items), the market map (both the widget version and the
experimental Flame version), the vendor list, order status (both the
awaiting-payment QR view and the post-payment pickup-code view), and the
vendor create-stall form. Screens that need data mock the network via
`package:http/testing.dart`'s `MockClient` (see
`vendor_list_screen_test.dart`, `order_status_screen_test.dart`,
`vendor_create_stall_screen_test.dart` for the pattern) — `test_helpers.dart`'s
`pumpGolden` wires up the same providers `main.dart` does. Pass
`settle: false` for a screen with a continuously-running game loop (see
`market_map_game_screen_test.dart`) — `pumpAndSettle()` waits for frames to
stop being scheduled, which never happens for a live Flame game, so the
test would hang; pump a fixed number of frames manually instead.

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
job runs `flutter test` on every push/PR — that step is *expected to fail*
until golden PNGs are committed, and that's fine; it's the real check, and a
future regression needs it to still be able to go red (don't "fix" this by
adding `continue-on-error`). Right after it, a separate `flutter test
--update-goldens` step renders every golden image fresh regardless of
whether the strict step passed, and the workflow uploads them as the
`golden-test-renders` artifact. Download it from the workflow run's Summary
page, eyeball the screenshots, and if they look right, copy them into
`test/golden/*/goldens/` and commit — from then on, plain `flutter test`
will catch real regressions. (`flutter_test`'s own automatic `failures/`
diff output only kicks in when a reference image already exists but doesn't
match; it stays empty while there's no baseline at all, which is why the
explicit `--update-goldens` step is needed here.)

## Status

Written and reviewed for consistency against the backend's request/response
shapes, but this environment has no Flutter/Dart SDK — and its network
policy blocks both the SDK download host (`storage.googleapis.com`) and
`pub.dev` — so `flutter analyze`, `flutter run`, and `flutter test`
(including generating the golden tests' reference images) have not actually
been run against this code. Treat it as unverified until you run it locally
with `scripts/run_dev.sh` or the manual steps above.
