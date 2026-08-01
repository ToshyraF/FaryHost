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

`MarketMapGameScreen` (`lib/features/customer/market_game/`) is the
customer home (`AuthGate` routes here, not straight to the plain list —
that's still reachable via the app bar's "ดูแบบรายการ" button), rendered
with [Flame](https://flame-engine.org) (`MarketFlameGame` + `FlameGame`
components for the ground, player, and stalls) rather than plain widgets.

This wasn't the first design. It started as a plain-widget screen
(`MarketMapScreen`, since deleted) — a `CustomPainter` ground plus
`Icon`/`Container`/`DecoratedBox` markers — because this sandbox had no
network access to fetch image assets or verify an untested new package.
Once a licensed sprite pack was uploaded directly by the user (not fetched
from a URL, so that constraint no longer applied), Flame got a genuine,
first-time try as an experimental alternative living alongside the widget
version, reachable from that screen's app bar rather than replacing it —
specifically so a broken Flame integration couldn't take down the
customer's only way to order. After several rounds of CI fixes and
user-uploaded golden screenshots confirmed it rendered correctly end to
end (see "Bugs found only from a real screenshot" below), the user asked
to keep only the game version, and the widget screen was deleted outright.
`MarketMapGameScreen` is now the sole implementation, not a
fallback-guarded experiment.

Stalls are laid out in a fixed grid derived from their index in the vendor
list (deterministic, not random, so the map looks the same on every load).
Tapping empty ground walks the avatar there, tapping a stall walks to it
and opens that stall's menu, and walking close enough to any stall without
tapping it directly auto-opens its menu too — each `StallComponent` tracks
its own `wasNear` flag, checked every `update()` tick against `_nearRadius`,
edge-triggering once per approach rather than every frame in range
(tapping a stall directly sets `wasNear = true` immediately so the walk-in
landing on it doesn't also fire the proximity trigger right after). Every
stall stays tappable regardless of avatar position (no functional gate),
since this is a real ordering app first.

### Sprite sheet and character selection

The avatar is a real pixel-art sprite sheet, not hand-drawn — a hand-coded
`CustomPainter` grid was the approach through several earlier redesigns
(chibi portrait, then an original full-body character) while this sandbox
had no way to fetch or verify an actual image asset, but the user later
supplied a licensed sprite pack directly (upload, not a fetched URL), which
removed that constraint. `assets/sprites/character_01.png` through
`character_10.png` are the "character overworld" sprites from *MyPixelWorld
Special Pack 01* (MPWSP01) by scarloxy (https://scarloxy.itch.io/mpwsp01),
confirmed commercially usable with no attribution requirement per the
pack's own description — see `assets/sprites/CREDITS.txt` for the full
license text and provenance. Each sheet is a 128x128 grid of 4x4 frames
(32x32 each): row 0 = facing down, row 1 = left, row 2 = right, row 3 =
up/back; columns 0-3 are a 4-frame walk cycle.

`CharacterSprite` (`lib/features/customer/character_sprite.dart`) crops and
scales one frame from a sheet for the character-picker grid — `Image.asset`
loads the whole sheet, a `Stack` + `Positioned` with explicit
`left`/`top`/`width`/`height` (all four values given directly) shifts the
desired frame into view, and the outer `ClipRect` cuts off the rest;
`FilterQuality.none` keeps the pixel edges crisp when scaled up. The first
version used `OverflowBox` + `alignment: Alignment.topLeft` instead of
`Positioned`, which rendered the avatar completely invisible in a real
render (caught from a user-uploaded golden screenshot, not CI — `flutter
test --update-goldens` only checks that *a* frame renders without
throwing, not that it looks right) — the exact same class of bug as an
earlier `Align`-in-`Stack` issue on the original hand-drawn avatar, both
fixed the same way: explicit `Positioned` with all four values, never a
fractional `Align`/`OverflowBox` alignment for sprite/UI-part placement in
this codebase. `CharacterState` (`lib/core/state/character_state.dart`)
persists which of the 10 characters the customer picked via
`shared_preferences`, the same pattern as `AuthState`'s session
persistence; `CharacterSelectScreen` is a tap-to-pick grid of all 10
down-facing idle frames, reachable two ways: from the map's app bar at any
time (pushed on top, pops back on pick), or — per a later user request —
`mandatory: true` right after registering a new customer account, wired
through `AuthGate` in `main.dart`. `AuthState.register()` sets a
`justRegistered` flag (cleared by `AuthState.clearJustRegistered()`, which
`CharacterSelectScreen` calls instead of `Navigator.pop()` when
`mandatory`) that `AuthGate` checks after the vendor-role branch: a
freshly-registered customer lands on the mandatory character picker (no
back button — there's nothing pushed to pop to) before ever seeing the
market map, while an ordinary login (existing account) skips straight to
`MarketMapGameScreen` as before. Flame's `PlayerComponent` draws from the
same sprite sheets directly (see below), not through `CharacterSprite`.

### Game Boy-style step movement, camera-follow, and D-pad

Movement used to be a free continuous slide: tapping anywhere moved the
avatar straight to that point over a fixed-duration tween, with a separate
timer cycling the walk-frame column for the same window. That had a real
race — tapping a new destination before the previous walk's window elapsed
replaced the timer field with the new animation's timer, but a stale
delayed callback from the *old* call still fired and cancelled whatever
the field pointed to by then (the new one), snapping the walk frame back
to standing while the avatar was still sliding. Since tapping repeatedly
is the normal way to explore a market, this fired constantly and looked
like the walk animation randomly freezing mid-stride (reported by the
user as "เดินหาย...ไม่เสถียรเลย").

Two more requests followed directly from playing with it: keep the avatar
from ever sliding off the visible screen on maps taller than the viewport
(the camera already followed the player — see below — but the player's
*own* position was never clamped to the world bounds at all; `walkTo()`
would happily move it to any tapped point, including ones outside the map
entirely, which is what the user meant by "ไม่อยากให้เดินหลุดหน้าจอ"), and
make movement feel like an old handheld game — discrete steps, also
drivable with directional buttons, not just a tap-to-anywhere slide.

`MarketFlameGame._stepInDirection` is now the single method that ever
moves the player: every call advances exactly `_stepSize` (32px) in one of
the four cardinal directions, clamps the result to the world bounds
(`_avatarClampMargin` — fixing the off-screen bug above), and calls
`player.stepTo(target, direction)`, which just sets the facing direction
and advances the walk frame by one — no per-call timer of its own, unlike
the old `walkTo()`/per-move animation this replaced, which also fully
retires the timer race described above. Two ways feed `_stepInDirection` a
stream of steps, and starting either one always cancels the other
(`_moveTimer`/`_activeDpadDirection`/`_pendingPath` are the single shared
source of truth for whichever is active): holding one of the four `_Dpad`
buttons (bottom-left corner overlay in `market_map_game_screen.dart`,
plain `Container`+`Icon` circles, not an image) fires one immediate step
then repeats every `_stepDuration` (160ms) until released; tapping the
ground or a stall instead calls `_buildPath`, which turns the straight-line
distance to the target into a queue of cardinal-direction steps (greedily
stepping whichever axis has more remaining distance each turn, so the path
looks like a staircase rather than one axis fully done before the other),
and the game drains that queue on the same cadence. `MapDirection` (the
direction enum) is a public type for this reason — the D-pad buttons live
in a different file (`market_map_game_screen.dart`) from where the enum is
declared (`market_flame_game.dart`).

All of this movement orchestration lives on `MarketFlameGame` rather than
on `PlayerComponent`, since a component can't easily reach back to its
parent game for the world bounds needed to clamp each step — the game
(which already owns `size`/`_worldHeight`) drives movement and
`PlayerComponent` stays a dumb renderer that only knows how to take the
one step it's told. The proximity auto-open logic above needed no changes
at all for this redesign — it already re-checks distance every `update()`
tick regardless of *how* `player.position` changes, so it works
identically whether the avatar moves in continuous slides or discrete
steps.

The camera itself follows the player vertically and is clamped to the
map's extent (`camera.follow(player, verticalOnly: true)` in `onLoad`,
plus a manual clamp of `camera.viewfinder.position.y` in `update()` — not
`camera.setBounds`, whose bounds-shape API/import didn't match the Flame
version CI resolves) in `market_flame_game.dart`, so a map taller than the
viewport (more vendors than fit on screen at once) scrolls as the player
walks toward the bottom rows instead of clipping — no horizontal follow
since the grid's fixed column count always fits the screen width exactly.

### Bugs found only from a real screenshot, not CI

`PlayerComponent` uses the same licensed sprite sheet as the character
picker (see above) rather than loading it through Flame's own `Images`
asset cache — it reads the bytes itself via `rootBundle.load(assetPath)` +
`instantiateImageCodec` in its own `onLoad()`, so it doesn't need to adopt
Flame's asset-path-prefix convention just to reuse a path already declared
in `pubspec.yaml`. `render()` skips drawing (leaves the component
transparent) while that decode is still in flight, then picks it up
automatically once done since the game loop re-renders every frame anyway
— this was deliberately kept non-blocking after a first attempt moved the
`await` into `MarketFlameGame.onLoad()` itself (so the decoded `Image`
could be passed straight into `PlayerComponent`'s constructor, no nullable
field) and a user-uploaded golden screenshot showed the *entire* map blank
— not just the player, the ground and stall markers too — because Flame's
`GameWidget` shows nothing at all until the game's own top-level `onLoad()`
future resolves, and that decode (a genuine engine round-trip through the
image codec, not just a microtask) didn't complete within the golden
test's fixed pump budget. Reverted to per-component decoding so the map
renders immediately regardless of how long the sprite takes; the golden
test (`market_map_game_screen_test.dart`) additionally wraps a short real
delay in `tester.runAsync()` before its pumps, since `tester.pump(duration)`
only advances the fake clock used for Timers/animations and doesn't by
itself guarantee a real async engine callback like this one has actually
completed. The vendor name labels had a matching but separate bug —
`TextComponent`'s `TextPaint` didn't specify `fontFamily: 'Loma'`, so Thai
stall names rendered as empty boxes too (Flame text doesn't inherit the
app's `ThemeData` the way a widget `Text` does); fixed by setting it
explicitly, same as `flutter_test_config.dart` already does for the
widget-tree side. None of these threw an exception, so `flutter test
--update-goldens` reported them all as passing — only a real screenshot
revealed the problems, which is why CI green should only ever be read as
"compiles and runs," never as "renders correctly," for anything visual in
this app. `render(Canvas canvas)` does a single
`canvas.drawImageRect(sheet, srcRect, dstRect, ...)` per frame (`srcRect`
picked by the facing row and walk-frame column) — the same core hook
every built-in Flame shape component implements internally, so this stays
low-exposure to unverified Flame API surface; "right" doesn't need a
mirror transform since the sheet already has distinct left/right frames.

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

Any `Icon` widget has the same problem — no `MaterialIcons` font loaded
means it renders as an empty tofu box in golden screenshots instead of the
actual glyph. First caught on the now-deleted widget map's stall markers
(`Icons.storefront`) from a user-uploaded screenshot rather than CI (this
doesn't throw, it just silently renders wrong); the market map's current
D-pad (`Icons.keyboard_arrow_*` — see "Market map" above) has the exact
same cosmetic problem for the same reason, as does `WelcomeScreen`'s own
`Icons.storefront`. A fix was attempted in `flutter_test_config.dart`
(loading `packages/flutter/fonts/MaterialIcons-Regular.otf` the same way
as the Thai font) but that asset path doesn't exist in the Flutter SDK
version CI resolves and hard-crashed every test instead, so it was
reverted — this is still an open, known issue, not yet fixed.

## Golden tests

`test/golden/` has widget-level golden (screenshot) tests for the screens
that render meaningfully without a live backend: welcome, login, register,
cart (empty + with items), the market map, the character select grid (both
its normal poppable form and the `mandatory: true` form shown right after
registering, which has no back button), the vendor list, order status
(both the awaiting-payment QR view and the post-payment pickup-code view),
and the vendor create-stall form. Screens that need data mock the network via
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
