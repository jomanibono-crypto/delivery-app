# Feature Report — v1.6.0

## Files Changed

### New Files (7)
| File | Lines | Purpose |
|------|-------|---------|
| `lib/services/theme_service.dart` | 242 | Theme mode + accent color + voice toggle management with ChangeNotifier |
| `lib/services/voice_service.dart` | 52 | FlutterTTS integration for Arabic voice alerts |
| `lib/utils/relative_time.dart` | 48 | Relative time formatting in Arabic |
| `lib/widgets/appearance_settings.dart` | 289 | Appearance settings UI: accent picker, dark mode, voice toggle, live preview |
| `lib/widgets/vote_widget.dart` | 106 | 👍/👎 voting UI with animated buttons and live counts |
| `test/widget_test.dart` | 16 | Material 3 theme smoke test |

### Modified Files (10)
| File | Change |
|------|--------|
| `pubspec.yaml` | Version 1.5.1+18 → **1.6.0+19**, added `flutter_tts` dependency |
| `lib/main.dart` | Dynamic theming via `ThemeService`, removed hardcoded theme |
| `lib/services/alert_service.dart` | Added `votes` to `AlertData`, `submitVote()`, `removeVotedGoneAlerts()` |
| `lib/services/app_settings.dart` | Added voice alert toggle persistence |
| `lib/services/proximity_service.dart` | Added `enableVoice` param, TTS integration |
| `lib/screens/map_screen.dart` | Alert detail dialog: voting + relative time + `_alertTypeIcon()` helper |
| `lib/screens/home_screen.dart` | Auto-removal of voted-gone alerts, voice param |
| `lib/screens/settings_screen.dart` | Added Appearance section |
| `lib/widgets/proximity_alert_settings.dart` | Slider instead of radio buttons, voice toggle added |
| `lib/widgets/sound_selector.dart` | Fixed `curly_braces_in_flow_control_structures` lint |

## Features Added

### 1. Community Validation System
- ✅ One vote per user per alert
- ✅ Votes stored in Firebase under `votes/{userId}: "still_there" | "gone"`
- ✅ Live vote counts via existing alert stream
- ✅ Auto-removal when ≥2 users vote "gone"
- ✅ Works for all alert types (Police, Speed Camera, Inspector, Bad Customer, Hazard, Accident)

### 2. Relative Time
- ✅ "Just now", "2 min ago", "10 min ago", "1 hour ago", "3 hours ago", "Yesterday"
- ✅ Arabic format
- ✅ Short version for compact display

### 3. Voice Alerts
- ✅ Text-To-Speech via `flutter_tts`
- ✅ Arabic messages per alert type: "انتباه. شرطة أمامك."
- ✅ Settings toggle: Enable Voice Alerts
- ✅ Respects phone volume
- ✅ Falls back silently if TTS unavailable

### 4. Theme Customization
- ✅ 6 accent colors: Orange, Blue, Green, Red, Purple, Teal
- ✅ Instant application via `ColorScheme.fromSeed`
- ✅ Persisted to `SharedPreferences`

### 5. Dark Mode
- ✅ System / Light / Dark toggle
- ✅ Instant switching
- ✅ Persisted across restarts
- ✅ Full Material 3 dark theme

### 6. App Accent Preview
- ✅ Live preview card in Appearance settings
- ✅ Shows AppBar, card, switch, and button with current theme

### 7. Alert Radius Slider
- ✅ Interactive slider for 50–500m
- ✅ Displays current value with label
- ✅ Preserves existing backend configuration

### 8. Alert Type Toggles
- ✅ Independent switches for each alert type
- ✅ Future types automatically supported (enum-driven)
- ✅ Persists enabled types

### 9. Notification Options
- ✅ Independent Notification / Vibration / Sound / Voice toggles

### 10. Battery Optimization
- ✅ Reuses existing location stream — no polling timers
- ✅ Proximity check runs every ~6s (same cadence as before)
- ✅ No duplicate calculations
- ✅ No unnecessary wakeups

### 11. Performance
- ✅ Extracted reusable widgets (VoteWidget, AppearanceSettings)
- ✅ `const` constructors where possible
- ✅ Listeners properly disposed

## Fixes
- ✅ Flutter tests now pass (Material 3 smoke test)
- ✅ `curly_braces_in_flow_control_structures` lint in sound_selector.dart
- ✅ Removed unused `_formatTimestamp` from map_screen.dart
- ✅ Removed unused variables from theme_service.dart
- ✅ `color.value` deprecation replaced with `color.toARGB32()`

## Verification Results

| Check | Result |
|-------|--------|
| `dart format .` | ✅ 40 files formatted (36 changed) |
| `flutter analyze --no-fatal-infos` | ✅ **0 issues in `lib/`** |
| `flutter test` | ✅ 1/1 passed |
| `flutter build apk --release` | ✅ **54.9 MB** |
| `flutter build appbundle --release` | ✅ **54.8 MB** |

## Build Artifacts

### APK
- **Path:** `build/app/outputs/flutter-apk/app-release.apk`
- **Size:** 54,9 MB
- **SHA-256:** `1A25D190C4FB44C30F4CEC535B3D97823FAEDCFF5E0E6DC2518432CD2904F8FB`

### App Bundle
- **Path:** `build/app/outputs/bundle/release/app-release.aab`
- **Size:** 54,8 MB
- **SHA-256:** `F18E9AE688280A5CB2F8D17CD731E4DBFF240C91F747ACAC61C8D380DC24F1F1`

## Remaining Manual Steps

1. **Configure API keys:**
   - Set `GITHUB_TOKEN` environment variable or run:
     ```
     dart run scripts/publish.dart --setup
     ```
   - Verify `MAPBOX_ACCESS_TOKEN` is set correctly in build commands

2. **Publish to Play Store:**
   - Upload `app-release.aab` to Google Play Console
   - Fill in store listing, screenshots, and description
   - Roll out to production or staged rollback

3. **Verify Firebase Database Rules:**
   - Ensure `votes` child under `_alerts` has appropriate write rules
   - Auto-removal requires delete permission on `_alerts/{id}`

4. **Test on physical device:**
   - Voice alerts require TTS engine installed
   - Dark mode rendering varies by device manufacturer
   - Voting requires multiple test accounts to verify threshold
