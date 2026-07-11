# Changelog

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
