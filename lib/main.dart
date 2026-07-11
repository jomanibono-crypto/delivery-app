import 'dart:async';
import 'dart:ui';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/firebase_service.dart';
import 'services/alert_service.dart';
import 'services/proximity_service.dart';
import 'services/app_settings.dart';
import 'services/theme_service.dart';
import 'services/voice_service.dart';
import 'services/map_cache_service.dart';
import 'services/map_camera_service.dart';
import 'config/mapbox_config.dart';
import 'utils/firebase_path.dart';

/// ID of the notification channel used by the foreground location service.
/// Must match the notificationChannelId passed to AndroidConfiguration below.
const String _locationChannelId = 'glovo_mate_location';

/// Unified location-update interval used by BOTH the foreground stream
/// (location_service.dart) and the background-service Timer. Keeping this in
/// one place guarantees identical cadence everywhere.
const Duration kLocationInterval = Duration(seconds: 3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check — Play Integrity on release, Debug provider on debug builds.
  // Enforcement must be enabled manually in the Firebase Console > App Check.
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
  );

  // Pass through unhandled Flutter errors to Crashlytics
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };

  // Pass through unhandled asynchronous Dart errors
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Enable Firebase Realtime Database offline persistence (caches data
  // locally so the app works without internet; syncs on reconnect).
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  FirebaseDatabase.instance.setPersistenceCacheSizeBytes(
    10 * 1024 * 1024,
  ); // 10 MB

  // Request battery optimization exemption so background location survives
  // Doze mode on Android 6+. This is non-blocking — the user can skip it.
  if (await Permission.ignoreBatteryOptimizations.status.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }

  // Create the foreground-service notification channel BEFORE configuring
  // the service. On Android 8+, startForeground() crashes with
  // "Bad notification for startForeground" if the channel doesn't exist yet.
  await _createLocationNotificationChannel();

  await configureBackgroundService();

  // Load theme settings BEFORE rendering splash so the accent color is known
  final themeService = ThemeService();
  await themeService.load();

  // Preload services in parallel — non-blocking, runs alongside splash
  unawaited(Future.wait([
    // Pre-warm map tile cache around Agadir so tiles load faster
    MapCacheService.preWarm(MapCameraService.defaultCenter),
    // Pre-initialize TTS so voice alerts are ready immediately
    VoiceService().initialize(),
    // Preload app settings
    AppSettings().load(),
    // Preload app settings extended
    AppSettings().loadExtended(),
    // Pre-cache map marker assets (icon fonts, images)
    _preloadAssets(),
  ]));

  runApp(const GlovoMateApp());
}

/// Create the notification channel required by the foreground service.
/// This MUST run before any startForeground() call.
Future<void> _createLocationNotificationChannel() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const channel = AndroidNotificationChannel(
    _locationChannelId, // ← must match notificationChannelId below
    'تتبع الموقع',
    description: 'إشعار دائم أثناء تتبع الموقع في الخلفية',
    importance: Importance.low, // low = no sound, but persistent
    showBadge: false,
  );
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

/// Preload common assets required by the map and UI.
/// This runs asynchronously before the first frame, so visual assets
/// are cached by the time the user reaches the home screen.
Future<void> _preloadAssets() async {
  try {
    // Cache the Mapbox tile URL (triggers DNS resolution + TLS handshake)
    await DefaultCacheManager().getSingleFile(MapboxConfig.mapboxTileUrl
        .replaceAll('{z}', '10')
        .replaceAll('{x}', '512')
        .replaceAll('{y}', '341'));
    debugPrint('[Startup] Tile preload completed.');
  } catch (_) {
    // Non-critical — skip silently
  }
  debugPrint('[Startup] Asset preload completed.');
}

/// Configure the background service before runApp.
Future<void> configureBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      // Channel must already exist (created in main() above).
      notificationChannelId: _locationChannelId,
      initialNotificationTitle: 'GlovoMate',
      initialNotificationContent: 'تتبع الموقع قيد التشغيل',
      // A valid small icon resource is REQUIRED for startForeground on
      // Android 8+ — a missing/null icon throws "Bad notification".
      // @mipmap/ic_launcher is generated by Flutter and guaranteed to exist.
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

/// Background service entry point.
///
/// PART 1: This isolate owns the ACTUAL GPS-read + Firebase-write loop,
/// completely independent of any UI/widget lifecycle. When the app is closed,
/// the UI State is destroyed but THIS Timer keeps running (the foreground
/// service keeps the process alive). So other members continue to see fresh
/// positions even after the user closes the app.
///
/// Reads `group_code` / `user_name` / `user_icon` from shared_preferences
/// (saved by the "remember session" feature) since this isolate has no access
/// to the UI's widget state.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Each isolate needs its own Firebase initialization.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check for the background isolate.
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
  );

  debugPrint('[BgService] onStart invoked.');

  // ── Acquire wake lock to prevent CPU sleep in Doze mode ──
  try {
    await WakelockPlus.enable();
    debugPrint('[BgService] Wake lock acquired.');
  } catch (e) {
    debugPrint('[BgService] Wake lock failed: $e');
  }

  StreamSubscription<DatabaseEvent>? chatSubBg;
  StreamSubscription<DatabaseEvent>? alertsSubBg;
  int foregroundNotifCounter = 0;
  final proximityBg = ProximityService(FlutterLocalNotificationsPlugin());
  final alertService = AlertService();
  List<AlertData> cachedAlerts = [];
  service.on('stop').listen((event) async {
    debugPrint('[BgService] stop requested.');
    chatSubBg?.cancel();
    alertsSubBg?.cancel();
    await WakelockPlus.disable();
    service.stopSelf();
  });

  // ── Periodic alive-signal: log keepalive and re-acquire wake lock ──
  // Android 12+ deep-doze can suspend timer-based tasks even in foreground
  // services. The wake lock + this periodic tick keeps the CPU alive.
  Timer.periodic(const Duration(seconds: 30), (_) async {
    foregroundNotifCounter++;
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    debugPrint('[BgService] Alive tick #$foregroundNotifCounter');
  });

  // Read saved session (group code + user name) from shared_preferences.
  final prefs = await SharedPreferences.getInstance();
  final groupCode = prefs.getString('group_code');
  final userName = prefs.getString('user_name');
  final userIcon = prefs.getString('user_icon');

  if (groupCode == null || userName == null) {
    debugPrint('[BgService] No saved session — GPS loop NOT started.');
    return;
  }

  // Re-authenticate anonymously if needed. Firebase Auth persists the token
  // to disk, so this is idempotent (returns the same UID across isolates).
  try {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      debugPrint('[BgService] Auth failed — no UID. GPS loop NOT started.');
      return;
    }
    debugPrint('[BgService] Authenticated. uid=$uid, group=$groupCode');

    // ── Notifications plugin (for chat messages in background) ──
    final notifPlugin = FlutterLocalNotificationsPlugin();
    const notifSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await notifPlugin.initialize(notifSettings);
    // Ensure the channel exists for chat notifications
    final androidNotif = notifPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    const chatChannel = AndroidNotificationChannel(
      'proximity_channel_v3',
      'Proximity Alerts',
      description: 'Notifications when group members are nearby',
      importance: Importance.max,
    );
    await androidNotif?.createNotificationChannel(chatChannel);

    // ── Chat message listener (shows notification when app is closed) ──
    try {
      final chatRef = FirebaseDatabase.instance.ref('live/${sanitizeFirebaseKey(groupCode)}/_chat');
      chatSubBg = chatRef.orderByChild('timestamp').onValue.listen((event) {
        final snap = event.snapshot;
        if (!snap.exists) return;
        final data = snap.value is Map
            ? snap.value as Map<dynamic, dynamic>
            : null;
        if (data == null) return;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        data.forEach((key, value) {
          if (value is! Map) return;
          final senderId = (value['userId'] as String?) ?? '';
          if (senderId == uid) return;
          final ts = (value['timestamp'] as num?)?.toInt() ?? 0;
          if (ts < nowMs - 60000) return; // only messages within last minute
          final senderName = (value['name'] as String?) ?? 'عضو';
          final msgText = (value['message'] as String?) ?? '';
          debugPrint('[BgService] Chat: $senderName: $msgText');
          notifPlugin.show(
            3000 + senderName.hashCode,
            '📩 $senderName',
            msgText,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'proximity_channel_v3',
                'Proximity Alerts',
                importance: Importance.max,
                priority: Priority.max,
                showWhen: true,
                playSound: true,
                enableVibration: true,
                visibility: NotificationVisibility.public,
                autoCancel: true,
                category: AndroidNotificationCategory.message,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
          );
        });
      });
    } catch (e) {
      debugPrint('[BgService] Chat listener setup failed: $e');
    }

    // ── Expired marker cleanup (run once on start) ──
    try {
      final deleted = await alertService.cleanupExpiredAlerts(groupCode);
      final msgDeleted = await alertService.cleanupExpiredMessages(groupCode);
      if (deleted > 0 || msgDeleted > 0) {
        debugPrint(
          '[BgService] Cleanup: $deleted alerts, $msgDeleted messages removed',
        );
      }
    } catch (_) {}

    // ── Alert marker listener for proximity checking ──
    try {
      final alertsRef = FirebaseDatabase.instance.ref(
        'live/${sanitizeFirebaseKey(groupCode)}/_alerts',
      );
      alertsSubBg = alertsRef.onValue.listen((event) {
        final snap = event.snapshot;
        if (!snap.exists) {
          cachedAlerts = [];
          return;
        }
        final data = snap.value as Map<dynamic, dynamic>? ?? {};
        final list = <AlertData>[];
        data.forEach((key, val) {
          if (val is Map) {
            list.add(AlertData.fromMap(val, key as String, groupCode));
          }
        });
        cachedAlerts = list;
      });
    } catch (e) {
      debugPrint('[BgService] Alerts listener setup failed: $e');
    }

    // ── THE GPS LOOP: fires every [kLocationInterval] (3s) ──
    // This is what keeps Firebase updated even when the app is closed.
    int gpsTick = 0;
    Timer.periodic(kLocationInterval, (timer) async {
      gpsTick++;
      try {
        // Quick permission/GPS check — skip silently if unavailable so the
        // timer doesn't spam errors when GPS is off.
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return;
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }

        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );

        // Write directly via the shared static function.
        await FirebaseService.writeLocationToFirebase(
          groupCode: groupCode,
          userId: uid,
          name: userName,
          lat: position.latitude,
          lng: position.longitude,
          speed: position.speed,
          icon: userIcon,
        );

        // Push a history point every 10th tick (~30s) for route tracking.
        if (gpsTick % 10 == 0) {
          await FirebaseService.writeHistoryPoint(
            groupCode: groupCode,
            userId: uid,
            lat: position.latitude,
            lng: position.longitude,
            speed: position.speed,
          );
        }

        // Proximity check against alert markers (run every ~6s to save battery)
        if (gpsTick % 2 == 0 && cachedAlerts.isNotEmpty) {
          final bgSettings = AppSettings();
          proximityBg.checkProximity(
            myLat: position.latitude,
            myLng: position.longitude,
            alerts: cachedAlerts,
            groupCode: groupCode,
            alertDistance: bgSettings.alertDistance,
            enabledTypes: bgSettings.enabledAlertTypes.split(','),
            enableNotification: bgSettings.alertNotificationEnabled,
            enableVibration: bgSettings.alertVibrationEnabled,
            enableSound: bgSettings.alertSoundEnabled,
            enableVoice: bgSettings.alertVoiceEnabled,
          );
        }

        final now = DateTime.now();
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        final ss = now.second.toString().padLeft(2, '0');
        debugPrint(
          '[BgService] Tick: lat=${position.latitude.toStringAsFixed(5)}, '
          'lng=${position.longitude.toStringAsFixed(5)}, '
          'speed=${position.speed.toStringAsFixed(1)}m/s, '
          'written at $hh:$mm:$ss',
        );
      } catch (e, s) {
        debugPrint('[BgService] Tick error: $e');
        FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
      }
    });
  } catch (e, s) {
    debugPrint('[BgService] Auth/setup failed: $e');
    FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
  }
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return false;
}

class GlovoMateApp extends StatefulWidget {
  const GlovoMateApp({super.key});

  @override
  State<GlovoMateApp> createState() => _GlovoMateAppState();
}

class _GlovoMateAppState extends State<GlovoMateApp> {
  late final ThemeService _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = _themeService.accentColor;
    return MaterialApp(
      title: 'GlovoMate',
      debugShowCheckedModeBanner: false,
      theme: _themeService.lightTheme(accent),
      darkTheme: _themeService.darkTheme(accent),
      themeMode: _themeService.flutterThemeMode,
      home: SplashScreen(accentColor: accent),
    );
  }
}
