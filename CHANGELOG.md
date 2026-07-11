# Changelog

## v1.6.9 — Fix blue map on startup & duplicated bottom navigation

### Bug Fixes
- **Fixed blue map on startup (Bug #1)** — The FlutterMap widget is now hidden behind a `_mapTilesReady` flag. After `onMapReady` fires, a 1.5-second timer gives tiles time to load before the map is revealed. On tile-failure fallback, the timer shortens to 500ms. The loading screen ("جارٍ تحديد موقعك...") covers the map until tiles are ready. The user never sees a blue ocean, empty tiles, or (0,0) camera.
- **Fixed duplicated bottom navigation (Bug #2)** — MapScreen had its own Scaffold with bottom nav, and was also embedded inside HomeScreen's Scaffold which also had a bottom nav. This created nested Scaffolds. Added `embedded` parameter to MapScreen — when true, it returns only the map content without a Scaffold wrapper. HomeScreen passes `embedded: true` when showing the map directly.
- **Removed nested Scaffolds** — MapScreen's standalone mode (still has Scaffold + bottom nav) is used only when navigated to directly. No more double bottom nav, no flicker, no duplicate widgets.

### Technical
- `lib/screens/map_screen.dart` — Added `_mapTilesReady`, `_mapRevealTimer`, `widget.embedded`. Build method gated behind both `_initialLocationReady` and `_mapTilesReady`. Standalone path returns Scaffold with AppBar + body + bottom nav. Embedded path returns only `mapContent` (no Scaffold).
- `lib/screens/home_screen.dart` — Passes `embedded: true` to MapScreen.

## v1.6.8 — Fix map loading freeze

[previous entries...]
