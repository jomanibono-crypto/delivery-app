# Changelog

## v1.6.7 — Loading Before Map & Smart Camera

### Features
- **Loading before map** — MapScreen now shows a modern loading screen with location icon and "جارٍ تحديد موقعك..." until the user's location is ready. The FlutterMap widget is only rendered after a valid location is obtained. The user never sees the blue ocean or (0,0) coordinates.
- **Smart camera (Feature 2)** — Two behaviors after first GPS location:
  - **Alone:** Centers on the user at zoom 16.
  - **Group exists:** Centers on the user immediately, waits 2 seconds, then smoothly animates to show all nearby members with proper padding.
- **Last known location** — If the device has a cached GPS position, the map immediately centers there. Otherwise it falls back to Agadir until GPS data arrives from Firebase.
- **Manual interaction respected** — If the user pans/zooms the map manually, the camera is never forced back.

### Bug Fixes
- Fixed duplicate `dispose` method in `map_screen.dart`.
- Removed obsolete `_cameraInitialized` / `_loadingTimedOut` mechanism.

### Technical
- `lib/screens/map_screen.dart` — Replaced `_cameraInitialized` with `_initialLocationReady`. Added `_smartCameraTimer` for 2-second group-expand delay. Added `_buildLocationLoadingScreen()` widget. Map rendering gated behind `!_initialLocationReady`. Old loading overlay and timeout error banner removed.

## v1.6.6 — (skipped, version consumed by publish script)

## v1.6.5 — Fix startup freeze & duplicate alert notifications

[previous entries...]
