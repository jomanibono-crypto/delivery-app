# Changelog

## v1.6.8 — Fix map loading freeze

### Bug Fixes
- **Fixed loading screen freeze** — When `Geolocator.getLastKnownPosition()` returns null (e.g., first install, no cache), the loading screen stayed stuck forever waiting for Firebase data. Now the app immediately falls back to `Geolocator.getCurrentPosition()` with an 8-second timeout. If that also fails, the map is shown with the Agadir fallback center. The user never sees an infinite spinner.
- **Reliable map startup** — The loading screen now resolves within 1-2 seconds on most devices instead of potentially hanging indefinitely.

### Technical
- `lib/screens/map_screen.dart` — `_initCamera()` now has 3 stages: (1) last known position, (2) direct GPS fetch with timeout, (3) Agadir fallback. Added `dart:async` import for `.timeout()`.

## v1.6.7 — Loading Before Map & Smart Camera

[previous entries...]
