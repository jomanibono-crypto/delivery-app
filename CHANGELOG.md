# Changelog

## v1.6.5 — Fix startup freeze & duplicate alert notifications

### Bug Fixes
- **Fixed startup freeze** — Added a 20-second timeout to splash screen initialization. If Firebase auth, update check, or session resume hangs, the user now sees an error message with a Retry button. The app will never get stuck on an infinite loading spinner.
- **Fixed duplicate alert notifications** — Alert notifications are now handled globally by `AlertNotificationService` (lives for the app's lifetime, not tied to any screen). A per-session `Set<String>` tracks already-notified alert IDs. Notifications appear immediately when a new alert is created on any screen (Map, Chat, Settings, Home, etc.). Navigating away and back never replays old notifications.

### Improvements
- **Global alert listener** — `AlertNotificationService` starts in `HomeScreen._startCoreServices()` and listens to Firebase alerts regardless of which screen is visible.
- **Removed duplicate MapScreen logic** — `_showAlertNotification()` and `_seenAlertIds` removed from `map_screen.dart`. The map only renders markers; all notification decisions are centralized.
- **Startup reliability** — Added `TimeoutException` handling to every Firebase call in `_initApp()`. The animation controller is properly disposed on retry.

### Technical
- `lib/services/alert_notification_service.dart` — New file. Singleton service with `startListening(groupCode)`, `stopListening()`, `clearCache()`. Uses `orderByChild('timestamp').limitToLast(50)` for efficient alert polling.
- `lib/screens/splash_screen.dart` — Added 20s `_initTimeout`, error state with retry button, timeouts on Firebase calls.
- `lib/screens/home_screen.dart` — Added `AlertNotificationService().startListening(widget.groupCode)` in `_startCoreServices()`.
- `lib/screens/map_screen.dart` — Removed `_showAlertNotification()`, `_seenAlertIds`, `_listenToAlerts()` notification logic.
