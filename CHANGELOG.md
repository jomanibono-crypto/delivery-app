# Changelog

## v1.8.0 — Auto-update, Map Loading, Sound Preview, Test Buttons, Startup Performance

### New Features
- **Automatic Update Improvement** — On launch, if a new version is found, the APK downloads automatically in the background with a progress indicator shown on the splash screen. On completion, the package installer opens automatically.
- **Map Loading Experience** — A semi-transparent overlay with spinner and "Preparing map..." message is shown until tiles are revealed. Timeout protection prevents blocking forever.
- **Notification Sound Preview** — Each sound in the selector now has a "▶ Preview" button that plays the sound immediately without changing the selection. Selecting a sound also plays a preview.
- **Send Test Notification** — New button in Settings that displays a local notification, plays the selected sound, vibrates (if enabled), and speaks the configured TTS voice (if enabled).
- **Test Vibration** — New button in Settings that vibrates using the current settings.
- **Startup Performance** — Map tiles are pre-warmed, TTS is pre-initialized, app settings are preloaded, and assets are pre-cached before the first frame. All service initialization runs in parallel without blocking.

### Files Changed
- `lib/services/notification_service.dart` — Added `previewSound()` and `sendTestNotification()` methods.
- `lib/widgets/sound_selector.dart` — Added "▶ Preview" button per sound tile, preview plays on selection.
- `lib/screens/splash_screen.dart` — Auto-download update with progress bar on splash; no blocking dialog.
- `lib/screens/map_screen.dart` — Added loading overlay with "Preparing map..." + spinner until tiles reveal.
- `lib/screens/settings_screen.dart` — Added "Send Test Notification" and "Test Vibration" buttons.
- `lib/main.dart` — Added `_preloadAssets()`, `Future.wait` for parallel init of TTS, settings, tile cache.
- `pubspec.yaml` — Version bumped to 1.8.0+41.
- `CHANGELOG.md` — Updated with v1.8.0 entry.

### Technical
- Sound preview uses a temporary notification channel that is deleted after play.
- Map overlay auto-disappears when `_tilesRevealed` is set to true.
- All startup preloading is non-blocking (`unawaited`) — the splash screen renders immediately.
- Zero new dependencies added; all features use existing packages.

## v1.7.3 — Health Dashboard

### New Features
- **Health Dashboard** — New screen accessible from Settings. Provides real-time monitoring of every system component.
- **Live Status Cards** — Green/Yellow/Red indicators for GPS, Internet, Firebase, Background Service, Notifications, Vibration, Map Engine, and Auto Update.
- **GPS Details** — Latitude, longitude, accuracy, speed, heading, altitude, provider, permission state, background permission.
- **Network Status** — Connection state, estimated ping latency, connection type.
- **Firebase Status** — Authentication state, database connection, last read/write success.
- **Group Info** — Online/offline member counts, current group ID.
- **Map Status** — Current zoom, camera position, loaded markers, map readiness, tile loading state.
- **System Info** — App version, build number, device model, Android version.
- **Diagnostic Tools** — Individual test buttons for GPS, Firebase, Internet, Notifications, Vibration, and Auto Update.
- **Full Diagnostic** — Runs all checks simultaneously and shows pass/fail results.
- **Report Export** — Generates a formatted health report copied to the clipboard.

### Files Added
- `lib/services/health_service.dart` — Singleton service that collects all health data from existing services (Geolocator, Firebase, HTTP, PackageInfo).
- `lib/screens/health_dashboard.dart` — Full-screen Material 3 dashboard with all status cards, diagnostic buttons, and export.
- `lib/screens/settings_screen.dart` — Added navigation button to Health Dashboard in the Appearance section.

### Technical
- No polling loops — all data collected on-demand via `_refresh()` or individual diagnostics.
- Uses existing `Geolocator`, `FirebaseDatabase`, `http` packages (no new dependencies).
- All listeners properly disposed.

## v1.7.2 — (skipped, version consumed by publish script)

## v1.7.1 — MapScreen rebuild: clean architecture, validation fixes

[previous entries...]
