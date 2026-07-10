# Changelog

## v1.6.3 — Crash Fix & Navigation Improvement

### Bug Fixes
- **Fixed crash from infinite recursion** — The `removeVotedGoneAlerts` method in `alert_service.dart` created a read-delete-trigger loop with the Firebase `onValue` stream, causing rapid resource exhaustion and app closure after ~5 seconds. Added a re-entry guard flag to prevent recursive calls.

### Improvements
- **Direct map navigation** — App now opens directly to the Map Screen after initialization, removing the intermediate "Tracking active" placeholder screen.
- **Faster startup** — No more waiting on the "Tracking active" screen; services initialize in background while the map loads.
- **Removed dead UI** — "Tracking active ✓", "Your location is shared with the group", "Tap the map to view members", and "Open map" button have been removed.
- **Improved startup stability** — Re-entrant guard prevents alert cleanup from overwhelming the Firebase listener.

### Technical
- `lib/screens/home_screen.dart` — Added `_showMapDirectly` flag; `build()` renders `MapScreen` inline after init; removed `MuteBanner` import; added `_isRemovingAlerts` guard.
- `scripts/publish.dart` — Fixed `_getFirebaseToken()` to fall back to Firebase CLI OAuth token when the API key has Android app restrictions.

## v1.6.2 — (skipped, version consumed by publish script)

## v1.6.1 — Community Validation, Theme Customization, Voice Alerts & More

[Previous changelog entries...]
