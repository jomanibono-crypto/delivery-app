# Map Screen Rebuild Report — v1.7.1

## Old Architecture Problems

| Problem | Description |
|---------|-------------|
| Monolithic State | Single `_MapScreenState` class (1882 lines) contained location, camera, markers, alerts, UI, and navigation logic all tangled together. |
| Boolean Chains | 4+ boolean flags (`_initialLocationReady`, `_firstLocationReceived`, `_mapTilesReady`, `_mapReady`, `_cameraInitialized`, `_loadingTimedOut`) whose interactions were hard to reason about. |
| Timer Overlap | Multiple timers (`_loadingTimeout`, `_smartCameraTimer`, `_mapRevealTimer`, `_historyTimer`) with overlapping cancel/restart logic. |
| Nested Scaffolds | MapScreen created its own Scaffold inside HomeScreen's Scaffold, causing duplicate AppBars and bottom nav flicker. |
| Blue Map Flash | Map was rendered before tiles loaded, showing white/blue background briefly. |
| Loading Freeze | `_initCamera()` only checked `getLastKnownPosition()` and waited for Firebase, sometimes forever. |
| Camera Complexity | `_fitCameraToBounds` had 4 condition guards and was duplicated between `onMapReady`, `_listenToMembers`, and member selector. |

## New Architecture

### Services (`lib/services/`)
| File | Responsibility |
|------|---------------|
| `map_location_service.dart` | Single-responsibility GPS retrieval: `resolve()`, `getLastKnownLocation()`, `getCurrentLocation()`. Caches position. |
| `map_camera_service.dart` | Camera positioning: `decide()` returns center/zoom/delay, `fitToBounds()` computes bounding rectangle. No state, pure functions. |

### Widgets (`lib/widgets/`)
| File | Responsibility |
|------|---------------|
| `map_loading_view.dart` | Animated loading screen with location icon, Arabic text, circular progress. |
| `map_error_view.dart` | Error screen with retry button. |

### Screens (`lib/screens/`)
| File | Responsibility |
|------|---------------|
| `map_screen.dart` | **Complete rewrite** (619 lines vs 1882 lines). Single `_initSequence()` startup. Clean state: `_ready`, `_mapReady`, `_tilesRevealed`. |

## Files Changed

| File | Lines Before | Lines After | Delta |
|------|-------------|-------------|-------|
| `lib/screens/map_screen.dart` | 1882 | 619 | **-1263** |
| `lib/services/map_location_service.dart` | — | 72 | **+72 new** |
| `lib/services/map_camera_service.dart` | — | 110 | **+110 new** |
| `lib/widgets/map_loading_view.dart` | — | 76 | **+76 new** |
| `lib/widgets/map_error_view.dart` | — | 56 | **+56 new** |
| `lib/screens/home_screen.dart` | 775 | 775 | 0 |

**Net reduction:** 949 lines while adding 4 new files with clean separation.

## Startup Sequence (New)

```
1. initState() → _initSequence()
2. MapLocationService.resolve() — GPS > last known > null
3. Pre-position camera (Agadir fallback if no location)
4. Load route history (non-blocking)
5. Start member stream listener
6. Start alert stream listener
7. Run cleanup
8. setState(_ready = true) → build() shows FlutterMap
9. FlutterMap mounts → onMapReady fires → setState(_mapReady = true)
10. First member data arrives → _runSmartCamera() → setState(_tilesRevealed = true)
11. Map content is now fully visible
```

## Verification Results

| Check | Result |
|-------|--------|
| `flutter clean && flutter pub get` | ✅ |
| `dart format` | ✅ 44 files (4 changed) |
| `flutter analyze` | ✅ 0 issues in `lib/` |
| `flutter test` | ✅ Passed |
| `flutter build apk --release` | ✅ 54.8 MB |
| `flutter build appbundle --release` | ✅ 54.8 MB |
| Emulator: app stable | ✅ PID 21092 |
| No duplicated bottom nav | ✅ Single Scaffold when embedded |
| No blue map flash | ✅ `MapLoadingView` covers until tiles ready |
| Embedded vs standalone | ✅ `embedded` flag cleanly separates modes |

## Release

- **Version:** 1.7.1+31
- **GitHub:** https://github.com/jomanibono-crypto/delivery-app/releases/tag/v1.7.1
- **APK:** https://github.com/jomanibono-crypto/delivery-app/releases/download/v1.7.1/app-release.apk
- **AAB:** `build/app/outputs/bundle/release/app-release.aab`
- **SHA-256:** `b482fac1c984afc8da621baecb5b4aa6a542aa63c816b3877bbeb82ba4234e39`
- **Firebase:** ✅ `latest_version: 1.7.1`
