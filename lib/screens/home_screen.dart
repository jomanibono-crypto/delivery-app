import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/local_storage_service.dart';
import '../services/app_settings.dart';
import '../services/permission_service.dart';
import '../services/haversine.dart';
import '../services/map_cache_service.dart';
import 'map_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';

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

  // OPTIMIZATION: pre-warm map tiles once (for the user's location) so the
  // map screen loads instantly when opened. Only triggers on the first valid
  // position to avoid repeated background downloads.
  bool _tilesPreWarmed = false;

  // Track which members already triggered a notification this session
  final Set<String> _notifiedMembers = {};

  // Track processed message keys so we don't re-notify
  final Set<String> _notifiedMessages = {};
  bool _chatScreenActive = false;

  // ── Lifecycle state for safe permission-flow resume ──
  bool _permissionsRequested = false;     // have we shown the flow at least once?
  bool _awaitingPermissionReturn = false; // did we send the user to Settings?
  bool _servicesStarted = false;          // have notifications+location started?

  @override
  void initState() {
    super.initState();
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
    _permissionsRequested = true;
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

    // ── Load saved proximity threshold before any proximity check runs ──
    try {
      await _appSettings.load();
      // F1: load the user's saved emoji icon
      _myIcon = await _localStorage.getUserIcon() ?? '🧑';
    } catch (e) {
      debugPrint('[Home] AppSettings/icon load failed: $e');
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

    if (!mounted) return;

    // ── Location tracking ──
    try {
      await _locationService.initialize();
      _startLocationUpdates();
      _listenToMembers();
      _listenToMessages();
      if (mounted) setState(() => _isTracking = true);
    } on GpsDisabledException {
      // GPS is off — show a friendly dialog with a button to open settings.
      _servicesStarted = false; // allow retry after user enables GPS
      if (mounted) {
        setState(() => _errorMessage =
            'GPS معطّل — يرجى تفعيل خدمة الموقع لمتابعة التتبع');
        _showGpsDisabledDialog();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'فشل في تتبع الموقع: $e');
    }
  }

  /// Friendly dialog shown when the device GPS/location service is off.
  void _showGpsDisabledDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.location_disabled, color: Colors.red),
              SizedBox(width: 10),
              Text('خدمة الموقع معطّلة'),
            ],
          ),
          content: const Text(
            'يرجى تفعيل خدمة الموقع (GPS) حتى يتمكن التطبيق من تتبع موقعك ومشاركته مع المجموعة.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لاحقاً'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _locationService.openLocationSettings();
                // Mark that we're awaiting the user to return from settings
                // so resume handling can retry startup once.
                _awaitingPermissionReturn = true;
              },
              icon: const Icon(Icons.settings),
              label: const Text('فتح الإعدادات'),
            ),
          ],
        ),
      ),
    );
  }

  void _startLocationUpdates() {
    _locationSubscription = _locationService.positionStream.listen((position) {
      _myLat = position.latitude;
      _myLng = position.longitude;
      // F5: capture the user's speed (m/s). May be 0/-1 when unavailable.
      _mySpeed = position.speed;

      // OPTIMIZATION: on the first valid position, pre-warm map tiles for the
      // user's area so the map screen is ready before they open it.
      if (!_tilesPreWarmed &&
          _myLat != 0.0 &&
          _myLng != 0.0) {
        _tilesPreWarmed = true;
        MapCacheService.preWarm(LatLng(_myLat, _myLng));
      }

      // Upload location to Firebase via SET (overwrite). Include the icon
      // so other members see the chosen emoji (F1).
      _firebaseService.updateUserLocation(
        groupCode: widget.groupCode,
        name: widget.userName,
        lat: _myLat,
        lng: _myLng,
        icon: _myIcon,
        speed: _mySpeed,
      );

      // Check proximity after each location update
      _checkProximity();
      // F4/F5: refresh the list so arrows + ETAs update live.
      if (mounted) setState(() {});
    }, onError: (error) {
      // AUDIT-E: handle the case where the user revokes location permission
      // or turns GPS off mid-session. The position stream emits an error.
      debugPrint('[Home] Location stream error: $error');
      if (!mounted) return;
      setState(() {
        _isTracking = false;
        _errorMessage = 'انقطع تتبع الموقع — تحقق من إذن الموقع/GPS.';
      });
    });
  }

  void _listenToMembers() {
    _membersSubscription =
        _firebaseService.watchGroupMembers(widget.groupCode).listen((event) {
      if (!mounted) return; // AUDIT-A: check before setState

      final snap = event.snapshot;
      if (!snap.exists) return;

      final data = snap.value as Map<dynamic, dynamic>?;
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
    }, onError: (e) {
      debugPrint('[Home] Members stream error: $e');
    });
  }

  // ──────────────────── Chat Message Listener ────────────────────

  void _listenToMessages() {
    _messagesSubscription =
        _firebaseService.watchMessages(widget.groupCode).listen((event) {
      if (!mounted) return;
      final snap = event.snapshot;
      if (!snap.exists) return;
      final data = snap.value as Map<dynamic, dynamic>?;
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
    }, onError: (e) {
      debugPrint('[Home] Messages stream error: $e');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _membersSubscription?.cancel();
    _messagesSubscription?.cancel();
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
          debugPrint('[Proximity] ${member['name']} in range but notifications '
              'are muted until ${DateTime.fromMillisecondsSinceEpoch(mutedUntil)}. Skipping.');
          continue;
        }
        debugPrint('[Proximity] 🔔 FIRING notification for "${member['name']}"');
        _notifiedMembers.add(entry.key);
        _notificationService.showProximityNotification(
          member['name'] as String,
          distance,
        );
      }

      // Remove from notified set if member moves away (so they can trigger again)
      if (distance > threshold && wasNotified) {
        debugPrint('[Proximity] "${member['name']}" moved out of range — '
            'resetting notified flag so they can trigger again.');
        _notifiedMembers.remove(entry.key);
      }
    }
  }

  // ──────────────────── Sorted Members List ────────────────────

  /// Return members sorted by distance to current user (closest first).
  List<MapEntry<String, Map<String, dynamic>>> _getSortedMembers() {
    final userId = _firebaseService.userId;
    final others = _members.entries.where((e) => e.key != userId).toList();

    others.sort((a, b) {
      final distA = calculateDistance(
        _myLat, _myLng, a.value['lat'] as double, a.value['lng'] as double,
      );
      final distB = calculateDistance(
        _myLat, _myLng, b.value['lat'] as double, b.value['lng'] as double,
      );
      return distA.compareTo(distB);
    });

    return others;
  }

  // ──────────────────── Format Helpers ────────────────────

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)}م';
    }
    return '${(meters / 1000).toStringAsFixed(1)}كم';
  }

  /// F5: rough ETA in human-readable Arabic.
  /// Falls back to 5 km/h walking speed if GPS speed is unavailable/zero.
  String _formatEta(double distanceMeters) {
    const fallbackMs = 5.0 * 1000 / 3600; // 5 km/h in m/s
    final effectiveSpeed = (_mySpeed > 0.5) ? _mySpeed : fallbackMs;
    final seconds = (distanceMeters / effectiveSpeed).round();

    if (seconds < 60) return '~$seconds ثانية';
    if (seconds < 3600) return '~${(seconds / 60).round()} دقيقة';
    return '~${(seconds / 3600).round()} ساعة';
  }

  // PART 2: movement-status smoothing. Tracks the last raw speed per member
  // so we only change the displayed status after 2 consistent readings,
  // avoiding flicker from GPS noise.
  final Map<String, double> _lastMemberSpeed = {};
  final Map<String, String> _stableMemberStatus = {};

  /// PART 2: classify speed (m/s) into a human-readable movement status.
  /// Returns a record (label, emoji). Speed < 0 means unavailable.
  ({String label, String emoji}) _classifyMovement(double speedMs) {
    if (speedMs < 0) return (label: 'غير متاح', emoji: '❓');
    final kmh = speedMs * 3.6;
    if (kmh < 1) return (label: 'واقف', emoji: '🛑');
    if (kmh < 7) return (label: 'يتمشى', emoji: '🚶');
    if (kmh < 25) return (label: 'بدراجة/سكوتر', emoji: '🚲');
    return (label: 'بسيارة/موتور', emoji: '🏍️');
  }

  /// PART 2: get the smoothed movement status for a member. Only changes the
  /// displayed status if the new classification matches the previous reading
  /// (requires 2 consistent readings to flip).
  ({String label, String emoji}) _getSmoothedStatus(
      String memberKey, double speedMs) {
    final newStatus = _classifyMovement(speedMs);
    final prev = _lastMemberSpeed[memberKey];
    final stable = _stableMemberStatus[memberKey];

    if (prev != null && (prev - speedMs).abs() < 0.5 && stable != null) {
      // Speed barely changed — keep the stable status.
      final parts = stable.split('|');
      return (label: parts[0], emoji: parts.length > 1 ? parts[1] : '');
    }

    // Speed changed meaningfully. Only commit the new status if the
    // classification actually differs from the committed one.
    final newKey = '${newStatus.label}|${newStatus.emoji}';
    if (stable != newKey) {
      // First sighting of this new status — record raw speed but don't flip
      // yet (wait for a 2nd consistent reading on the next tick).
      _lastMemberSpeed[memberKey] = speedMs;
      // Return the OLD stable status if we have one, else the new one.
      if (stable != null) {
        final parts = stable.split('|');
        return (label: parts[0], emoji: parts.length > 1 ? parts[1] : '');
      }
    } else {
      // Classification matches the committed one — keep it.
      _lastMemberSpeed[memberKey] = speedMs;
    }
    _stableMemberStatus[memberKey] = newKey;
    return newStatus;
  }

  /// F6: "آخر ظهور: منذ X دقيقة" from a Firebase epoch-ms timestamp.
  ///
  /// PART 1 FIX: Firebase's ServerValue.timestamp resolves to epoch
  /// milliseconds (UTC-based, timezone-independent). DateTime.now() is local,
  /// but `.millisecondsSinceEpoch` is ALWAYS epoch-based regardless of timezone.
  /// However, to be 100% explicit and avoid any confusion, we use `.toUtc()`
  /// on the now-side. Both sides are now guaranteed to be UTC epoch ms.
  String _formatLastSeen(int epochMs) {
    if (epochMs <= 0) return 'آخر ظهور: غير معروف';

    // PART 1 FIX: explicit UTC on the now-side for clarity + correctness.
    final nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
    final diff = nowUtc - epochMs;

    // PART 1 DEBUG: log raw values so we can verify the math is correct.
    final localNow = DateTime.now();
    debugPrint(
      '[LastSeen] rawTs=$epochMs '
      '(≈ ${DateTime.fromMillisecondsSinceEpoch(epochMs).toUtc().toIso8601String()} UTC), '
      'nowLocal=${localNow.toIso8601String()}, '
      'nowUtc=${DateTime.now().toUtc().toIso8601String()}, '
      'diffMs=$diff (${(diff / 60000).toStringAsFixed(1)} min)',
    );

    final minutes = (diff / 60000).floor();
    if (minutes < 1) return 'آخر ظهور: الآن';
    if (minutes < 60) return 'آخر ظهور: منذ $minutes دقيقة';
    final hours = (minutes / 60).floor();
    if (hours < 24) return 'آخر ظهور: منذ $hours ساعة';
    final days = (hours / 24).floor();
    return 'آخر ظهور: منذ $days يوم';
  }

  // ──────────────────── Build ────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('المجموعة: ${widget.groupCode}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: Chip(
                avatar: _isTracking
                    ? const Icon(Icons.gps_fixed, size: 16, color: Colors.green)
                    : const Icon(Icons.gps_off, size: 16, color: Colors.red),
                label: Text(
                  _isTracking ? 'GPS نشط' : 'GPS متوقف',
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _MuteBanner(localStorage: _localStorage),
          Expanded(
            child: _errorMessage.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.gps_off, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isTracking ? Icons.gps_fixed : Icons.gps_off,
                            size: 72,
                            color: _isTracking ? Colors.green : Colors.red.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isTracking ? 'التتبع نشط ✓' : 'التتبع متوقف',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _isTracking ? const Color(0xFF2E7D32) : Colors.red.shade400,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isTracking
                                ? 'موقعك يُشارك مع المجموعة\nاضغط على الخريطة لعرض الأعضاء'
                                : 'يرجى تفعيل الموقع من الإعدادات',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pushReplacement(context, MaterialPageRoute(
                                builder: (_) => MapScreen(groupCode: widget.groupCode, userName: widget.userName)),
                              );
                            },
                            icon: const Icon(Icons.map),
                            label: const Text('فتح الخريطة'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ──────────────────── Bottom Navigation ────────────────────

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'الخريطة'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'الدردشة'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
      ],
      onDestinationSelected: (index) {
        if (index == 0) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MapScreen(groupCode: widget.groupCode, userName: widget.userName)));
        } else if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(groupCode: widget.groupCode, userName: widget.userName)));
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SettingsScreen(groupCode: widget.groupCode, userName: widget.userName)));
        }
      },
    );
  }
}

/// F3: A self-refreshing banner shown at the top of the home screen when
/// notifications are snoozed. Displays the end time and a "cancel" button.
class _MuteBanner extends StatefulWidget {
  final LocalStorageService localStorage;
  const _MuteBanner({required this.localStorage});

  @override
  State<_MuteBanner> createState() => _MuteBannerState();
}

class _MuteBannerState extends State<_MuteBanner> {
  int _mutedUntil = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Re-check every 30s so an expired mute disappears automatically.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final until = await widget.localStorage.getMutedUntil();
    if (mounted) setState(() => _mutedUntil = until);
  }

  Future<void> _cancelMute() async {
    await widget.localStorage.setMutedUntil(null);
    if (mounted) setState(() => _mutedUntil = 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_mutedUntil <= 0) return const SizedBox.shrink();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_mutedUntil <= now) return const SizedBox.shrink();

    final endTime = DateTime.fromMillisecondsSinceEpoch(_mutedUntil);
    final hh = endTime.hour.toString().padLeft(2, '0');
    final mm = endTime.minute.toString().padLeft(2, '0');

    return Material(
      color: const Color(0xFFFFF3CD),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.notifications_off, color: Color(0xFF856404)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'الإشعارات متوقفة حتى $hh:$mm',
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  color: Color(0xFF856404),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: _cancelMute,
              child: const Text('إلغاء', style: TextStyle(color: Color(0xFF856404))),
            ),
          ],
        ),
      ),
    );
  }
}
