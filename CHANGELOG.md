# Changelog

## v1.9.0+42 — Security hardening, code cleanup & design refresh

### Security
- **Admin codes are now hashed.** `AdminService` stores SHA-256(salt + code) instead of plaintext codes. An attacker unpacking the APK can no longer read admin codes directly. Build-time override via `--dart-define=ADMIN_MASTER_CODE=xxxxx` for emergency access.
- **Constant-time comparison** for admin code verification to prevent timing attacks.
- **Brute-force lockout** — 3 failed attempts lock the admin panel for 30 seconds.

### Design refresh (new GlovoMate look)
- **New design system** under `lib/theme/` (app_colors, app_typography, app_spacing) — central source of truth for colors, typography, radii.
- **Common widgets**: `GlassCard`, `AppButton` (5 variants), `AppInput`, `AppSwitch`, `StatusPill`, `AppBottomNav`.
- **Splash screen** — deep indigo gradient, glass logo tile, animated loading dots.
- **Group screen** — gradient hero card, focused-state inputs, primary/tonal button pair.
- **Map screen** — dark theme map background, glass top bar with live indicator + group code, members floating card with glassmorphism, redesigned FABs.
- **Chat screen** — gradient indigo bubbles, glass input bar with gradient send button, custom chat header with status pill.
- **Blacklist screen** — gradient hero stats card, redesigned entry cards, integrated search, FAB add button.
- **Settings screen** — modern AppBar with gradient icon, switches to use `AppBottomNav` for consistency.
- **Home screen** — modern AppBar with gradient icon, `AppBottomNav` integration.

### Bug Fixes
- **Proximity channel id mismatch fixed.** `ProximityService` now binds to the versioned `proximity_channel_vN` (matching `NotificationService`) so the user's chosen sound and priority actually apply to alert proximity notifications.
- **Chat notifications no longer fire while user is in chat.** Replaced the always-`false` `_chatScreenActive` flag with a real `ForegroundScreenService`.

### Cleanup
- Removed dead `MapLoadingView` widget.

### Files Added
- `lib/theme/app_colors.dart` — full color palette + gradient/shadow tokens.
- `lib/theme/app_typography.dart` — typography scale (display, title, body, label, number, button).
- `lib/theme/app_spacing.dart` — 4pt-grid spacing tokens + radius tokens.
- `lib/widgets/glass_card.dart` — base card with optional gradient + shadow.
- `lib/widgets/app_button.dart` — unified button with 5 variants.
- `lib/widgets/app_input.dart` — themed text input.
- `lib/widgets/app_switch.dart` — themed toggle.
- `lib/widgets/status_pill.dart` — colored status badge.
- `lib/widgets/app_bottom_nav.dart` — floating glass-style bottom nav.
- `lib/services/foreground_screen_service.dart` — tracks the current foreground screen.

### Verification
- `flutter analyze lib/ --no-fatal-infos` → **No issues found.**
- APK build attempted but blocked by network timeouts (Connection timed out to storage.googleapis.com). Code is verified clean.

## v1.9.0+42 — Security hardening & code cleanup

### Security
- **Admin codes are now hashed.** `AdminService` stores SHA-256(salt + code) instead of plaintext codes. An attacker unpacking the APK can no longer read admin codes directly. Build-time override via `--dart-define=ADMIN_MASTER_CODE=xxxxx` for emergency access.
- **Constant-time comparison** for admin code verification to prevent timing attacks.
- **Brute-force lockout** — 3 failed attempts lock the admin panel for 30 seconds.

### Bug Fixes
- **Proximity channel id mismatch fixed.** `ProximityService` now binds to the versioned `proximity_channel_vN` (matching `NotificationService`) so the user's chosen sound and priority actually apply to alert proximity notifications. Previously the id was hardcoded to `v3`, so sound changes beyond v3 would no longer affect proximity alerts.
- **Chat notifications no longer fire while user is in chat.** Replaced the always-`false` `_chatScreenActive` flag with a real `ForegroundScreenService` that tracks the visible top-level screen (map/chat/blacklist/settings). Home listener now correctly suppresses chat pings when the user is already viewing the chat screen.

### Cleanup
- Removed dead `MapLoadingView` widget (unused; the map renders its own loading overlay).

### Files Added
- `lib/services/foreground_screen_service.dart` — Tracks the current foreground screen; exposed via `isActive(ForegroundScreen.chat)` etc.

### Files Changed
- `lib/services/admin_service.dart` — Rewritten with SHA-256 + salt + rate limit + master-code override.
- `lib/services/proximity_service.dart` — `channelId` is now mutable via `updateChannelId()`.
- `lib/main.dart` — Passes `channelId` to the background-service `ProximityService`.
- `lib/screens/home_screen.dart` — Replaces `_chatScreenActive` with `ForegroundScreenService` lookup.
- `lib/screens/{chat,map,blacklist,settings}_screen.dart` — Register/deregister with `ForegroundScreenService` in `initState`/`dispose`.
- `lib/widgets/map_loading_view.dart` — **Deleted** (dead code).

### Verification
- `flutter analyze lib/ --no-fatal-infos` → **No issues found.**

## v1.9.0 — Admin Mode, Message Deletion, Daily Statistics, Mapbox Restored

### New Features
- **Group Admin Mode** — Enter admin code (2010/2020/2030) from Settings to unlock admin panel. Admins can remove any member, delete any alert (police, radar, inspector, hazard, accident, bad customer, control).
- **Delete Own Chat Messages** — Long press on any message you sent to delete it. Message disappears immediately for all group members via Firebase realtime sync.
- **Daily Distance & Time Statistics** — Automatically tracks distance traveled (km), driving time, moving time, and stopped time. Resets every 24 hours. Data stored locally. View from Settings.
- **Mapbox Restored** — Mapbox raster tiles re-enabled with production token for map rendering.

### Files Added
- `lib/services/admin_service.dart` — Singleton that verifies admin codes 2010/2020/2030.
- `lib/screens/admin_panel_screen.dart` — Admin panel showing members list (with remove) and alerts list (with delete).
- `lib/services/daily_stats_service.dart` — Tracks daily KM, driving/moving/stopped time, persists to SharedPreferences, auto-resets at midnight.
- `lib/screens/stats_screen.dart` — Displays daily stats in card layout with icons.

### Files Changed
- `lib/services/firebase_service.dart` — Added `deleteMessage()` and `removeMemberFromGroup()` methods.
- `lib/screens/chat_screen.dart` — Long press on own message shows delete confirmation; message removed from Firebase.
- `lib/screens/settings_screen.dart` — Added "Admin Mode" section with code entry and panel navigation; added "Daily Stats" button.
- `lib/screens/home_screen.dart` — Integrates `DailyStatsService.updatePosition()` on each GPS tick; flushes on dispose.
- `pubspec.yaml` — Version bumped to 1.9.0+42.
- `CHANGELOG.md` — Updated with v1.9.0 entry.

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
