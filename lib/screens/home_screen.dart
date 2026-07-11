import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/local_storage_service.dart';
import '../services/app_settings.dart';
import '../services/permission_service.dart';
import '../services/haversine.dart';
import '../services/map_cache_service.dart';
import '../services/alert_service.dart';
import '../services/proximity_service.dart';
import '../services/alert_notification_service.dart';
import 'map_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'blacklist_screen.dart';

/// Home screen that initializes tracking services and provides navigation
/// to Map, Chat, and Settings screens.
class HomeScreen extends StatefulWidget {
  final String groupCode;
  final String userName;

  const HomeScreen({
    super.key,
    required this.groupCode,
    required this.userName,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

// Expose state so map/settings screens can access same params
class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirebaseService _firebaseService = FirebaseService();
  final LocationService _locationService = LocationService();
  final NotificationService _notificationService = NotificationService();
  final AppSettings _appSettings = AppSettings();
  final PermissionService _permissionService = PermissionService();
  final LocalStorageService _localStorage = LocalStorageService();

  StreamSubscription<DatabaseEvent>? _membersSubscription;
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<DatabaseEvent>? _messagesSubscription;

  // { userId: { name, lat, lng, online, icon } }
  Map<String, Map<String, dynamic>> _members = {};
  double _myLat = 0.0;
  double _myLng = 0.0;
  double _mySpeed = 0.0; // F5: user's current speed in m/s (from GPS)
  bool _isTracking = false;
  String _errorMessage = '';

  // F1: current user's chosen emoji (loaded from local storage)
  String _myIcon = '🧑';
  late String _userName;

  // OPTIMIZATION: pre-warm map tiles once (for the user's location) so the
  // map screen loads instantly when opened. Only triggers on the first valid
  // position to avoid repeated background downloads.
  bool _tilesPreWarmed = false;

  final AlertService _alertService = AlertService();
  final ProximityService _proximityService = ProximityService(
    FlutterLocalNotificationsPlugin(),
  );
  List<AlertData> _alertCache = [];
  StreamSubscription<List<AlertData>>? _alertsSubHome;

  // Track which members already triggered a notification this session
  final Set<String> _notifiedMembers = {};

  // Track processed message keys so we don't re-notify
  final Set<String> _notifiedMessages = {};
  final bool _chatScreenActive = false;

  // When true, show the map directly instead of the tracking placeholder
  bool _showMapDirectly = false;

  // ── Lifecycle state for safe permission-flow resume ──
  bool _awaitingPermissionReturn = false; // did we send the user to Settings?
  bool _servicesStarted = false; // have notifications+location started?

  @override
  void initState() {
    super.initState();
    _userName = widget.userName;
    // Observe app lifecycle so we can handle resume from Settings safely.
    WidgetsBinding.instance.addObserver(this);
    _initServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPermissionReturn) {
      // User came back from system Settings.
      // DO NOT re-trigger the dialog flow — just silently re-check status
      // and proceed (or warn) based on what was actually granted.
      _awaitingPermissionReturn = false;
      _handleResumeFromSettings();
    }
  }

  /// Called when the app resumes after the user was sent to Settings.
  /// Silently re-checks permissions and continues startup without dialogs.
  Future<void> _handleResumeFromSettings() async {
    final status = await _permissionService.checkCurrentStatus();
    if (!mounted) return;

    debugPrint(
      '[Resume] locationAlways=${status.locationAlwaysGranted}, '
      'batteryIgnored=${status.batteryOptimizationIgnored}',
    );

    if (!status.locationAlwaysGranted) {
      // Still not granted — show the warning, but don't crash or re-flow.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ لم يُمنح الموقع "دائماً" — إشعارات القرب لن تعمل موثوقةً في الخلفية.',
              textAlign: TextAlign.right,
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    // Whether or not "Always" was granted, try to finish starting services.
    // This also covers the case where the user just enabled GPS in settings.
    // _startCoreServices is idempotent, so retrying after enabling GPS works.
    if (_servicesStarted) {
      // Already started — check if GPS was just enabled and we should retry.
      final gpsOn = await _locationService.isLocationServiceEnabled();
      if (gpsOn && !_isTracking && mounted) {
        _servicesStarted = false; // allow the retry
      }
    }
    await _startCoreServices();
  }

  Future<void> _initServices() async {
    // ── Step 1: Request background permissions (may open Settings) ──
    _awaitingPermissionReturn = true;
    try {
      if (!mounted) return;
      await _permissionService.requestBackgroundPermissions(context: context);
    } catch (e) {
      debugPrint('[Home] Permission flow error: $e');
    } finally {
      _awaitingPermissionReturn = false;
    }

    if (!mounted) return;

    // ── Step 2-4: Start foreground service, notifications, location ──
    await _startCoreServices();
  }

  /// Start the foreground service + notifications + location tracking.
  /// Safe to call multiple times — guarded by [_servicesStarted].
  Future<void> _startCoreServices() async {
    if (!mounted) return;
    if (_servicesStarted) return; // idempotent
    _servicesStarted = true;

    // ── Load latest name + icon from local storage ──
    try {
      final savedName = await _localStorage.getUserName();
      if (savedName != null && savedName.isNotEmpty) _userName = savedName;
      _myIcon = await _localStorage.getUserIcon() ?? '🧑';
    } catch (e) {
      _myIcon = '🧑';
    }

    // ── Create/refresh presence node so security rules allow reads ──
    try {
      await _firebaseService.createPresenceNode(
        groupCode: widget.groupCode,
        name: _userName,
        icon: _myIcon,
      );
    } catch (e) {
      debugPrint('[Home] Presence node create failed: $e');
    }

    // ── Load saved proximity threshold and alert settings ──
    try {
      await _appSettings.load();
      await _appSettings.loadExtended();
    } catch (e) {
      debugPrint('[Home] AppSettings load failed: $e');
    }

    if (!mounted) return;

    // ── Foreground service + WakeLock ──
    try {
      await FlutterBackgroundService().startService();
    } catch (e) {
      debugPrint('[Home] Background service start skipped/failed: $e');
    }

    // Acquire a wake lock in the UI isolate too (belt AND suspenders)
    try {
      await WakelockPlus.enable();
      debugPrint('[Home] Wake lock acquired (UI).');
    } catch (e) {
      debugPrint('[Home] Wake lock failed (UI): $e');
    }

    if (!mounted) return;

    // ── Notifications ──
    try {
      await _notificationService.initialize();
      await _notificationService.requestPermissions();
    } catch (e) {
      debugPrint('[Home] Notification init failed: $e');
    }

    // ── Start global alert notification listener ──
    AlertNotificationService().startListening(widget.groupCode);

    if (!mounted) return;

    // ── Location tracking ──
    try {
      await _locationService.initialize();
      _startLocationUpdates();
      _listenToMembers();
      _listenToMessages();
      _listenToAlertProximity();
      if (mounted) {
        setState(() {
          _isTracking = true;
          _showMapDirectly = true;
        });
      }
    } on GpsDisabledException {
      // GPS is off — show a friendly dialog with a button to open settings.
      _servicesStarted = false; // allow retry after user enables GPS
      if (mounted) {
        setState(
          () => _errorMessage =
              'GPS معطّل — يرجى تفعيل خدمة الموقع لمتابعة التتبع',
        );
        _showGpsDisabledDialog();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'فشل في تتبع الموقع: $e');
    }
  }

  /// Friendly dialog shown when the device GPS/location service is off.
  void _showGpsDisabledDialog() {
    if (!mounted) return;
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.location_disabled_rounded,
                  color: theme.colorScheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'خدمة الموقع معطّلة',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          content: Text(
            'يرجى تفعيل خدمة الموقع (GPS) حتى يتمكن التطبيق من تتبع موقعك ومشاركته مع المجموعة.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لاحقاً'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _locationService.openLocationSettings();
                _awaitingPermissionReturn = true;
              },
              icon: const Icon(Icons.settings_rounded, size: 20),
              label: const Text('فتح الإعدادات'),
            ),
          ],
        ),
      ),
    );
  }

  void _startLocationUpdates() {
    _locationSubscription = _locationService.positionStream.listen(
      (position) {
        _myLat = position.latitude;
        _myLng = position.longitude;
        // F5: capture the user's speed (m/s). May be 0/-1 when unavailable.
        _mySpeed = position.speed;

        // OPTIMIZATION: on the first valid position, pre-warm map tiles for the
        // user's area so the map screen is ready before they open it.
        if (!_tilesPreWarmed && _myLat != 0.0 && _myLng != 0.0) {
          _tilesPreWarmed = true;
          MapCacheService.preWarm(LatLng(_myLat, _myLng));
        }

        // Upload location to Firebase via SET (overwrite). Include the icon
        // so other members see the chosen emoji (F1).
        _firebaseService.updateUserLocation(
          groupCode: widget.groupCode,
          name: _userName,
          lat: _myLat,
          lng: _myLng,
          icon: _myIcon,
          speed: _mySpeed,
        );

        // Check member proximity after each location update
        _checkProximity();
        // Check alert proximity with configured settings
        _proximityService.checkProximity(
          myLat: _myLat,
          myLng: _myLng,
          alerts: _alertCache,
          groupCode: widget.groupCode,
          alertDistance: _appSettings.alertDistance,
          enabledTypes: _appSettings.enabledAlertTypes.split(','),
          enableNotification: _appSettings.alertNotificationEnabled,
          enableVibration: _appSettings.alertVibrationEnabled,
          enableSound: _appSettings.alertSoundEnabled,
          enableVoice: _appSettings.alertVoiceEnabled,
        );
        // F4/F5: refresh the list so arrows + ETAs update live.
        if (mounted) setState(() {});
      },
      onError: (error) {
        // AUDIT-E: handle the case where the user revokes location permission
        // or turns GPS off mid-session. The position stream emits an error.
        debugPrint('[Home] Location stream error: $error');
        if (!mounted) return;
        setState(() {
          _isTracking = false;
          _errorMessage = 'انقطع تتبع الموقع — تحقق من إذن الموقع/GPS.';
        });
      },
    );
  }

  void _listenToMembers() {
    _membersSubscription = _firebaseService
        .watchGroupMembers(widget.groupCode)
        .listen(
          (event) {
            if (!mounted) return; // AUDIT-A: check before setState

            final snap = event.snapshot;
            if (!snap.exists) return;

            final data = snap.value is Map
                ? snap.value as Map<dynamic, dynamic>
                : null;
            if (data == null) {
              if (mounted) setState(() => _members.clear());
              return;
            }

            final updated = <String, Map<String, dynamic>>{};
            data.forEach((key, value) {
              // Skip internal metadata node — it's not a real member.
              if (key == '_meta') return;

              // AUDIT-A: defensive cast — value may not always be a Map.
              if (value is! Map) return;
              final member = value;

              updated[key] = {
                'name': (member['name'] as String?) ?? 'بدون اسم',
                'lat': (member['lat'] as num?)?.toDouble() ?? 0.0,
                'lng': (member['lng'] as num?)?.toDouble() ?? 0.0,
                'online': member['online'] as bool? ?? false,
                // F1: capture each member's chosen emoji (may be null).
                'icon': (member['icon'] as String?) ?? '',
                // F6: last-update timestamp (epoch ms) for "last seen".
                'timestamp': (member['timestamp'] as num?)?.toInt() ?? 0,
                // PART 2: member's current speed (m/s) for movement status.
                'speed': (member['speed'] as num?)?.toDouble() ?? 0.0,
              };
            });

            if (!mounted) return;
            setState(() => _members = updated);

            // Also check proximity when members list updates
            _checkProximity();
          },
          onError: (e) {
            debugPrint('[Home] Members stream error: $e');
          },
        );
  }

  // ──────────────────── Chat Message Listener ────────────────────

  void _listenToMessages() {
    _messagesSubscription = _firebaseService
        .watchMessages(widget.groupCode)
        .listen(
          (event) {
            if (!mounted) return;
            final snap = event.snapshot;
            if (!snap.exists) return;
            final data = snap.value is Map
                ? snap.value as Map<dynamic, dynamic>
                : null;
            if (data == null) return;

            data.forEach((key, value) {
              if (value is! Map) return;
              final msgId = key.toString();
              if (_notifiedMessages.contains(msgId)) return;

              final senderId = (value['userId'] as String?) ?? '';
              if (senderId == _firebaseService.userId) return;

              final senderName = (value['name'] as String?) ?? 'عضو';
              final msgText = (value['message'] as String?) ?? '';
              final senderIcon = (value['icon'] as String?) ?? '';

              _notifiedMessages.add(msgId);

              // Only notify if user is not actively viewing the chat screen
              if (!_chatScreenActive) {
                _notificationService.showChatMessageNotification(
                  senderName: senderName,
                  message: msgText,
                  senderIcon: senderIcon,
                );
              }
            });
          },
          onError: (e) {
            debugPrint('[Home] Messages stream error: $e');
          },
        );
  }

  bool _isRemovingAlerts = false;

  void _listenToAlertProximity() {
    _alertsSubHome = _alertService.watchAlerts(widget.groupCode).listen((
      alerts,
    ) {
      _alertCache = alerts.where((a) => a.type.isAlert).toList();
      if (!_isRemovingAlerts) {
        _isRemovingAlerts = true;
        _alertService
            .removeVotedGoneAlerts(widget.groupCode)
            .then((_) {
              _isRemovingAlerts = false;
            })
            .catchError((_) {
              _isRemovingAlerts = false;
            });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _membersSubscription?.cancel();
    _messagesSubscription?.cancel();
    _alertsSubHome?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  // ──────────────────── Proximity Check ────────────────────

  /// Compare each member's distance against the notification threshold.
  /// Fires a local notification if a member enters the radius.
  Future<void> _checkProximity() async {
    if (_myLat == 0.0 && _myLng == 0.0) {
      debugPrint('[Proximity] SKIP — my position is (0,0), not ready yet.');
      return;
    }

    final userId = _firebaseService.userId;
    final threshold = _appSettings.proximityThreshold;

    debugPrint(
      '[Proximity] CHECK START — members=${_members.length - 1} (excluding self), '
      'threshold=${threshold}m, myPos=($_myLat, $_myLng)',
    );

    // Edge case: no other members to compare against.
    if (_members.length <= 1) {
      debugPrint('[Proximity] No other members in the group yet.');
      return;
    }

    for (final entry in _members.entries) {
      // Skip self
      if (entry.key == userId) continue;

      final member = entry.value;
      final distance = calculateDistance(
        _myLat,
        _myLng,
        member['lat'] as double,
        member['lng'] as double,
      );

      final wasNotified = _notifiedMembers.contains(entry.key);
      debugPrint(
        '[Proximity] member="${member['name']}" '
        'dist=${distance.toStringAsFixed(1)}m '
        'inRange=${distance <= threshold} '
        'alreadyNotified=$wasNotified',
      );

      // Only notify once per session per member entering the threshold
      if (distance <= threshold && !wasNotified) {
        // F3: respect the snooze/mute window — skip the notification (but
        // still keep updating distance in the UI). We do NOT add the member
        // to _notifiedMembers, so once the mute expires they'll get notified.
        final mutedUntil = await _localStorage.getMutedUntil();
        final now = DateTime.now().millisecondsSinceEpoch;
        if (mutedUntil > now) {
          debugPrint(
            '[Proximity] ${member['name']} in range but notifications '
            'are muted until ${DateTime.fromMillisecondsSinceEpoch(mutedUntil)}. Skipping.',
          );
          continue;
        }
        debugPrint(
          '[Proximity] 🔔 FIRING notification for "${member['name']}"',
        );
        _notifiedMembers.add(entry.key);
        _notificationService.showProximityNotification(
          member['name'] as String,
          distance,
        );
      }

      // Remove from notified set if member moves away (so they can trigger again)
      if (distance > threshold && wasNotified) {
        debugPrint(
          '[Proximity] "${member['name']}" moved out of range — '
          'resetting notified flag so they can trigger again.',
        );
        _notifiedMembers.remove(entry.key);
      }
    }
  }

  // ──────────────────── Sorted Members List ────────────────────

  // ──────────────────── Build ────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_rounded,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('المجموعة: ${widget.groupCode}'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _isTracking
                      ? theme.colorScheme.tertiaryContainer
                      : theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isTracking
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isTracking ? 'GPS نشط' : 'GPS متوقف',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isTracking
                            ? theme.colorScheme.onTertiaryContainer
                            : theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _showMapDirectly
          ? MapScreen(groupCode: widget.groupCode, userName: widget.userName)
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.gps_off_rounded,
                        size: 40,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ──────────────────── Bottom Navigation ────────────────────

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: 'الخريطة',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'الدردشة',
        ),
        NavigationDestination(
          icon: Icon(Icons.block_outlined),
          selectedIcon: Icon(Icons.block),
          label: 'القائمة السوداء',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'الإعدادات',
        ),
      ],
      onDestinationSelected: (index) {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MapScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 2) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BlacklistScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 3) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        }
      },
    );
  }
}
