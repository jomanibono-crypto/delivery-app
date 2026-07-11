# Regression Fix Report — v1.7.4+34

## Root Causes

### Bug 1 — Loading screen never finishes

**Root cause:** `_mapCtrl.move(center, zoom)` was called in `_initSequence()` BEFORE the FlutterMap widget had been rendered. The MapController threw:
```
Exception: You need to have the FlutterMap widget rendered at least once before using the MapController.
```

This exception was caught by the `try/catch` in `_initSequence`, which set `_error` but **did not set `_ready = true`**. Since `_ready` stayed `false`, the build method kept returning the loading screen forever.

**Fix (3 changes):**
1. **Don't call `_mapCtrl.move()` before FlutterMap is mounted** — Instead of positioning the camera in `_initSequence`, store the target as `_pendingCamera` / `_pendingZoom` and apply it in `onMapReady` after FlutterMap is mounted.
2. **Safety timeout** — Added a 5-second `_initSafetyTimer` in `_initSequence` that forces `_ready = true` even if init blocks. Added a 5-second `_mapReadySafetyTimer` in `initState` that forces `_mapReady = true` if `onMapReady` never fires.
3. **Force ready on error** — The `catch` block now always sets `_ready = true` so the error UI is shown instead of an infinite loading screen.

### Bug 2 — Bottom Navigation disappeared

**Root cause:** The loading state of standalone MapScreen returned a `Scaffold` with `appBar` and `body` but **without `bottomNavigationBar`**. When the loading screen never finished (Bug 1), the user was stuck on a screen with no way to navigate to Chat, Blacklist, or Settings.

**Fix:** Added `bottomNavigationBar: _buildBottomNav()` to the loading Scaffold in standalone mode.

## Files Modified

| File | Changes |
|------|---------|
| `lib/screens/map_screen.dart` | Added `_pendingCamera`, `_pendingZoom` fields. Camera stored in `_initSequence`, applied in `onMapReady`. Added `_initSafetyTimer` (5s), `_mapReadySafetyTimer` (5s). Added `bottomNavigationBar` to loading Scaffold. Added `_initSafetyTimer?.cancel()` / `_mapReadySafetyTimer?.cancel()` in dispose. |

## Validation

| Test | Result |
|------|--------|
| Cold start 1 | ✅ PID 24792 |
| Cold start 2 | ✅ PID 24948 |
| Cold start 3 | ✅ PID 25076 |
| Cold start 4 | ✅ PID 25268 |
| Cold start 5 | ✅ PID 25353 |
| All show "Step 6/6: Ready" | ✅ |
| All show "onMapReady fired — applying pending camera" | ✅ |
| All show "Camera moved to LatLng" | ✅ |
| No "Init failed" errors | ✅ |
| No FATAL/CRASH | ✅ |
| 30s stability | ✅ PID 25353 |
| `flutter analyze` | ✅ 0 issues |
| `flutter build apk` | ✅ 55.3 MB |

## Verification Log (Cold Start #5)

```
[Map] Step 1/6: Resolving location...
[Map] Step 1/6 done — location=LatLng(37.421998, -122.084)
[Map] Step 2/6: Pending camera=... zoom=16.0
[Map] Step 3-4/6: Route history started
[Map] Step 5a/6: Member listener started
[Map] Step 5b/6: Alert listener started
[Map] Step 6/6: Ready=true — map should appear now
[Map] onMapReady fired — applying pending camera
[Map] Camera moved to LatLng(37.421998, -122.084) zoom=16.0
[Map] Smart camera: center=..., delay=true
[Map] Smart camera expanded to bounds
```
