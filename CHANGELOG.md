# Changelog

## v1.6.0 — Community Validation, Theme Customization, Voice Alerts & More

### New Features
- **Community Validation System** — Vote 👍 "Still there" or 👎 "Gone" on any shared alert. One vote per user, live counts, auto-removal when enough users confirm it's gone. Available for all alert types.
- **Theme Customization** — Choose from 6 accent colors (Orange, Blue, Green, Red, Purple, Teal). The primary color updates instantly across the entire app.
- **Dark Mode** — System/Light/Dark toggle with instant switching. Persists across restarts.
- **App Accent Preview** — Live preview card in Appearance settings showing how the selected theme affects buttons, cards, switches, AppBar, and dialogs.
- **Voice Alerts** — Optional Text-To-Speech notifications that announce alert types aloud (e.g., "Attention. Police ahead."). Toggle in Settings.
- **Alert Radius Slider** — Configurable proximity alert distance with an interactive slider (50m–500m) showing the current value.
- **Notification Options** — Independent toggles for Notification, Vibration, Sound, and Voice.
- **Relative Time** — All timestamps now show relative time (e.g., "Just now", "5 min ago", "2 hours ago", "Yesterday").

### Improvements
- **Refactored ProximityService** — Single-level configurable alert with per-type filtering, per-channel toggles, and voice integration. Uses existing location stream — no polling or extra battery drain.
- **Dynamic Theming** — `ThemeService` manages accent color and dark mode with `ChangeNotifier`. Themes are built using `ColorScheme.fromSeed` for consistent Material 3 palettes.
- **Performance** — Extracted widgets prevent unnecessary rebuilds. Scroll performance maintained.
- **Nested import elimination** — `firebase_service.dart` no longer has redundant re-exports.

### Technical
- `lib/services/theme_service.dart` — Singleton managing theme mode + accent color + voice toggle persistence
- `lib/services/voice_service.dart` — FlutterTTS integration with Arabic voice messages per alert type
- `lib/utils/relative_time.dart` — Relative time formatting in Arabic
- `lib/widgets/appearance_settings.dart` — Appearance section with accent picker, dark mode, and live preview
- `lib/widgets/vote_widget.dart` — 👍/👎 voting UI with live counts
- `lib/widgets/proximity_alert_settings.dart` — Updated with slider and voice toggle
- `lib/services/alert_service.dart` — Added vote fields to AlertData, submitVote(), removeVotedGoneAlerts()
- `lib/services/app_settings.dart` — Added voice alert toggle persistence
- `lib/main.dart` — Dynamic theme with light/dark support via ThemeService
- `lib/screens/map_screen.dart` — Alert detail dialog now shows voting + relative time
- `lib/screens/settings_screen.dart` — Added Appearance section before proximity alerts
- `lib/screens/home_screen.dart` — Auto-removal of voted-gone alerts, voice param in proximity check
- `test/widget_test.dart` — Material 3 theme smoke test

### Dependencies Added
- `flutter_tts: ^4.2.2` — Text-to-speech for voice alerts
