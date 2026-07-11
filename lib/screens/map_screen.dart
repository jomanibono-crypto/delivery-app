import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import '../config/mapbox_config.dart';
import '../services/firebase_service.dart';
import '../services/map_cache_service.dart';
import '../services/alert_service.dart';
import '../services/map_location_service.dart';
import '../services/map_camera_service.dart';
import '../services/haversine.dart';
import '../widgets/vote_widget.dart';
import '../widgets/map_error_view.dart';
import '../utils/relative_time.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'blacklist_screen.dart';

class MapScreen extends StatefulWidget {
  final String groupCode;
  final String userName;
  final bool embedded;

  const MapScreen({
    super.key,
    required this.groupCode,
    required this.userName,
    this.embedded = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ── Services ──
  final FirebaseService _fb = FirebaseService();
  final AlertService _alertSvc = AlertService();
  final MapLocationService _locationSvc = MapLocationService();
  final MapController _mapCtrl = MapController();

  // ── Subscriptions ──
  StreamSubscription<DatabaseEvent>? _membersSub;
  StreamSubscription<List<AlertData>>? _alertsSub;
  Timer? _historyTimer;
  Timer? _smartCameraDelay;
  Timer? _mapReadySafetyTimer;

  // ── Pending camera position (set before map is ready, applied in onMapReady) ──
  LatLng? _pendingCamera;
  double _pendingZoom = MapCameraService.defaultZoom;

  // ── State ──
  bool _mapReady = false;
  bool _tilesRevealed = false;
  bool _userInteracted = false;
  bool _gpsAnimated = false;
  bool _fellBackToOsm = false;
  String _tileUrl = MapboxConfig.mapboxTileUrl;
  int _tileErrors = 0;

  String? _error;

  // Use ValueNotifier so marker layers rebuild independently of FlutterMap
  final ValueNotifier<Map<String, Map<String, dynamic>>> _membersNotifier =
      ValueNotifier({});
  final ValueNotifier<List<AlertData>> _alertsNotifier =
      ValueNotifier([]);
  Map<String, Map<String, dynamic>> get _members => _membersNotifier.value;
  List<AlertData> get _alerts => _alertsNotifier.value;

  List<LatLng> _route = [];
  String? _followingMemberId;

  // ── Marker colors ──
  static const _colors = [
    Color(0xFF1565C0),
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF00ACC1),
    Color(0xFFD81B60),
  ];

  @override
  void initState() {
    super.initState();
    _mapReadySafetyTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_mapReady) {
        debugPrint('[Map] ⚠️ Map-ready safety timeout');
        setState(() => _mapReady = true);
      }
    });
    _initSequence();
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _alertsSub?.cancel();
    _historyTimer?.cancel();
    _smartCameraDelay?.cancel();
    _mapReadySafetyTimer?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  //  INITIALIZATION SEQUENCE
  // ═══════════════════════════════════════════════

  Future<void> _initSequence() async {
    try {
      // 1. Last known location (instant — no GPS)
      debugPrint('[Map] Step 1: Checking last known location...');
      final lastKnown = await _locationSvc.getLastKnownLocation();

      if (lastKnown != null) {
        debugPrint('[Map] Last known found: $lastKnown');
        _pendingCamera = lastKnown;
        _pendingZoom = 16.0;
      } else {
        debugPrint('[Map] No last known — defaulting to Agadir');
        _pendingCamera = MapCameraService.defaultCenter;
        _pendingZoom = MapCameraService.defaultZoom;
      }

      // 2. Run GPS, route, and cleanup in parallel
      Future.wait([
        _locationSvc.getCurrentLocation().then((gps) {
          if (gps != null && mounted && !_gpsAnimated) {
            _gpsAnimated = true;
            debugPrint('[Map] GPS acquired: $gps');
            if (_mapReady) {
              _mapCtrl.move(gps, 16.0);
            } else {
              _pendingCamera = gps;
              _pendingZoom = 16.0;
            }
          }
        }),
        _loadRoute(),
        _runCleanup(),
      ]);

      // 3–4. Periodic route refresh
      _historyTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadRoute(),
      );
      debugPrint('[Map] Route refresh started');

      // 5. Listeners (immediate, non-blocking)
      _listenMembers();
      debugPrint('[Map] Member listener started');
      _listenAlerts();
      debugPrint('[Map] Alert listener started');

      debugPrint('[Map] Init complete — waiting for onMapReady');
    } catch (e) {
      debugPrint('[Map] ❌ Init error: $e');
      if (mounted) {
        setState(() => _error = 'تعذّر تحميل الخريطة: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════
  //  DATA LISTENERS
  // ═══════════════════════════════════════════════

  void _listenMembers() {
    _membersSub = _fb.watchGroupMembers(widget.groupCode).listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value is! Map) return;
      final data = snap.value as Map<dynamic, dynamic>;

      final updated = <String, Map<String, dynamic>>{};
      data.forEach((key, value) {
        if (key == '_meta' || key == '_chat' || key == '_alerts') return;
        if (value is! Map) return;
        updated[key.toString()] = {
          'name': (value['name'] as String?) ?? 'بدون اسم',
          'lat': (value['lat'] as num?)?.toDouble() ?? 0.0,
          'lng': (value['lng'] as num?)?.toDouble() ?? 0.0,
          'online': value['online'] as bool? ?? false,
          'icon': (value['icon'] as String?) ?? '',
          'speed': (value['speed'] as num?)?.toDouble() ?? 0.0,
          'last_moved_at': (value['last_moved_at'] as num?)?.toInt() ?? 0,
          'timestamp': (value['timestamp'] as num?)?.toInt() ?? 0,
        };
      });

      if (!mounted) return;
      _membersNotifier.value = updated;

      // Smart camera on first data
      if (!_tilesRevealed && _mapReady) {
        _runSmartCamera();
      }

      // Follow member or fit bounds (but not if user manually panned)
      if (_followingMemberId != null && !_userInteracted) {
        _followMember();
      } else if (_followingMemberId == null && _tilesRevealed && !_userInteracted && _membersNotifier.value.length >= 3) {
        _fitBounds();
      }
    }, onError: (_) {});
  }

  void _listenAlerts() {
    _alertsSub = _alertSvc.watchAlerts(widget.groupCode).listen((alerts) {
      if (!mounted) return;
      _alertsNotifier.value = alerts.where((a) => !a.resolved).toList();
    });
  }

  // ═══════════════════════════════════════════════
  //  SMART CAMERA (one-time, first load only)
  // ═══════════════════════════════════════════════

  void _runSmartCamera() {
    final uid = _fb.userId;
    final me = _members[uid];
    if (me == null) return;
    final myLat = me['lat'] as double? ?? 0.0;
    final myLng = me['lng'] as double? ?? 0.0;
    if (myLat == 0.0 && myLng == 0.0) return;

    final myPos = LatLng(myLat, myLng);
    final decision = MapCameraService.decide(
      userPosition: myPos,
      userId: uid,
      members: _members,
    );

    _mapCtrl.move(decision.center, decision.zoom);

    if (decision.shouldDelay) {
      _smartCameraDelay?.cancel();
      _smartCameraDelay = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        final bounds = MapCameraService.fitToBounds(_members);
        _mapCtrl.move(bounds.center, bounds.zoom);
        debugPrint('[Map] Smart camera expanded to bounds');
      });
    }

    _tilesRevealed = true;
    if (mounted) setState(() {});
    debugPrint(
      '[Map] Smart camera: center=$myPos, delay=${decision.shouldDelay}',
    );
  }

  void _fitBounds() {
    if (_members.isEmpty || !_mapReady) return;
    final bounds = MapCameraService.fitToBounds(_members);
    _mapCtrl.move(bounds.center, bounds.zoom);
  }

  void _followMember() {
    if (_followingMemberId == null || !_mapReady) return;
    final m = _members[_followingMemberId];
    if (m == null) return;
    final lat = m['lat'] as double? ?? 0.0;
    final lng = m['lng'] as double? ?? 0.0;
    if (lat == 0.0 && lng == 0.0) return;
    _mapCtrl.move(LatLng(lat, lng), 17);
  }

  // ═══════════════════════════════════════════════
  //  MEMBER SELECTOR
  // ═══════════════════════════════════════════════

  void _selectMember(String id) {
    setState(() {
      _followingMemberId = id;
      _userInteracted = false;
    });
    _followMember();
  }

  void _showAll() {
    setState(() => _followingMemberId = null);
    final bounds = MapCameraService.fitToBounds(_members);
    _mapCtrl.move(bounds.center, bounds.zoom);
  }

  void _openMemberPicker() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final entries = _members.entries.toList();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'اختيار عضو',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...entries.map(
                (e) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: e.key == _fb.userId
                        ? _colors[0]
                        : _colors[(entries.indexOf(e) % (_colors.length - 1)) +
                              1],
                    child: (e.value['icon'] as String).isNotEmpty
                        ? Text(
                            e.value['icon'] as String,
                            style: const TextStyle(fontSize: 16),
                          )
                        : const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 18,
                          ),
                  ),
                  title: Text(
                    '${e.value['name']}${e.key == _fb.userId ? ' (أنت)' : ''}',
                  ),
                  trailing: e.key == _followingMemberId
                      ? Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        )
                      : const Icon(
                          Icons.chevron_left_rounded,
                          color: Colors.grey,
                        ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectMember(e.key);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════
  //  ALERTS & CONTEXT MENU
  // ═══════════════════════════════════════════════

  void _onLongPress(TapPosition tap, LatLng point) =>
      _showAlertContextMenu(point);

  void _showAlertContextMenu(LatLng point) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          title: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.error,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'إبلاغ عن',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: AlertType.values
                .where((t) => t.isAlert)
                .map(
                  (type) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: type.color.withValues(alpha: 0.15),
                      child: Text(
                        type.label.runes.isNotEmpty
                            ? String.fromCharCode(type.label.runes.first)
                            : '',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    title: Text(type.label),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _alertSvc.addAlert(
                        groupCode: widget.groupCode,
                        type: type,
                        lat: point.latitude,
                        lng: point.longitude,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم الإبلاغ عن ${type.label}'),
                            backgroundColor: const Color(0xFF2E7D32),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  void _showAlertDetail(AlertData alert) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: alert.type.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _alertIcon(alert.type),
                  color: alert.type.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  alert.type.label,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (alert.reason.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: alert.type.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: alert.type.color.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.report_rounded,
                        color: alert.type.color,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alert.reason,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (alert.note.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(alert.note, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                'أبلغ بواسطة: ${alert.userName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                relativeTime(alert.timestamp),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              VoteWidget(
                alert: alert,
                currentUserId: _fb.userId,
                onVote: (vote) async {
                  await _alertSvc.submitVote(
                    groupCode: widget.groupCode,
                    alertId: alert.id,
                    vote: vote,
                  );
                },
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDeleteAlert(alert);
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('حذف'),
              style: FilledButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                backgroundColor: theme.colorScheme.errorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAlert(AlertData alert) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('تأكيد الحذف'),
          content: const Text('هل أنت متأكد من حذف هذا البلاغ؟'),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                await _alertSvc.deleteAlert(widget.groupCode, alert.id);
              },
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _alertIcon(AlertType t) => switch (t) {
    AlertType.police => Icons.local_police_rounded,
    AlertType.speedTrap => Icons.speed_rounded,
    AlertType.control => Icons.supervisor_account_rounded,
    AlertType.hazard => Icons.warning_rounded,
    AlertType.accident => Icons.car_crash_rounded,
    AlertType.note => Icons.sticky_note_2_rounded,
    AlertType.badCustomer => Icons.person_off_rounded,
  };

  // ═══════════════════════════════════════════════
  //  MARKERS
  // ═══════════════════════════════════════════════

  List<Marker> _buildAlertMarkers() {
    return _alerts.map((alert) {
      return Marker(
        point: LatLng(alert.lat, alert.lng),
        width: 160,
        height: alert.note.isNotEmpty ? 88.0 : 56.0,
        child: GestureDetector(
          onTap: () => _showAlertDetail(alert),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: alert.type.color.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _alertIcon(alert.type),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  alert.type.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (alert.note.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    alert.note,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildMemberMarkers() {
    final uid = _fb.userId;
    final keys = _members.keys.toList();
    final markers = <Marker>[];
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final m = _members[key]!;
      final lat = m['lat'] as double;
      final lng = m['lng'] as double;
      final isMe = key == uid;
      final isFollowed = key == _followingMemberId;
      final ci = isMe ? 0 : (i % (_colors.length - 1)) + 1;
      final color = isFollowed ? const Color(0xFFFF9800) : _colors[ci];
      final label = '${m['name']}${isMe ? ' (أنت)' : ''}';

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 80,
          height: 64,
          child: GestureDetector(
            onTap: () => _showMemberPopup(key),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: (m['icon'] as String).isNotEmpty
                      ? Center(
                          child: Text(
                            m['icon'] as String,
                            style: const TextStyle(fontSize: 16),
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  void _showMemberPopup(String key) {
    final m = _members[key];
    if (m == null) return;
    final theme = Theme.of(context);
    final uid = _fb.userId;
    final isMe = key == uid;
    final name = m['name'] as String? ?? '';
    final icon = m['icon'] as String? ?? '';
    final online = m['online'] as bool? ?? false;
    final lat = m['lat'] as double? ?? 0.0;
    final lng = m['lng'] as double? ?? 0.0;
    final speedMs = m['speed'] as double? ?? 0.0;
    final speedKmh = speedMs * 3.6;
    final lastMoved = m['last_moved_at'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Stop duration
    String stopDuration = '';
    if (lastMoved > 0 && speedMs < 1) {
      final stoppedSec = (now - lastMoved) ~/ 1000;
      if (stoppedSec < 60) {
        stopDuration = 'منذ أقل من دقيقة';
      } else if (stoppedSec < 3600) {
        stopDuration = 'منذ ${stoppedSec ~/ 60} دقيقة';
      } else if (stoppedSec < 86400) {
        stopDuration = 'منذ ${stoppedSec ~/ 3600} ساعة';
      } else {
        stopDuration = 'منذ ${stoppedSec ~/ 86400} يوم';
      }
    }

    // Distance from me
    String distanceStr = '';
    final myData = _members[uid];
    if (myData != null && !isMe) {
      final myLat = myData['lat'] as double? ?? 0.0;
      final myLng = myData['lng'] as double? ?? 0.0;
      if (myLat != 0.0 && myLng != 0.0 && lat != 0.0 && lng != 0.0) {
        final dist = calculateDistance(myLat, myLng, lat, lng);
        distanceStr = dist < 1000
            ? '${dist.toStringAsFixed(0)} متر'
            : '${(dist / 1000).toStringAsFixed(1)} كم';
      }
    }

    // Battery (from Firebase data if available)
    final battery = m['battery'] as int?;
    final batteryStr = battery != null ? '🔋 $battery%' : 'البطارية غير متوفرة';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Drag handle
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              // Avatar + Name
              CircleAvatar(
                radius: 36,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: icon.isNotEmpty
                    ? Text(icon, style: const TextStyle(fontSize: 32))
                    : Icon(Icons.person_rounded, color: theme.colorScheme.primary, size: 32),
              ),
              const SizedBox(height: 12),
              Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: online ? Colors.green : Colors.grey, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(online ? 'متصل' : 'غير متصل',
                  style: TextStyle(color: online ? Colors.green : Colors.grey, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Info rows
              _infoRow(theme, Icons.speed_rounded, 'السرعة', speedKmh > 0 ? '${speedKmh.toStringAsFixed(1)} كم/ساعة' : '0 كم/ساعة'),
              if (stopDuration.isNotEmpty)
                _infoRow(theme, Icons.timer_rounded, 'متوقف', stopDuration),
              _infoRow(theme, Icons.location_on_rounded, 'الإحداثيات', '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'),
              if (distanceStr.isNotEmpty)
                _infoRow(theme, Icons.straighten_rounded, 'المسافة مني', distanceStr),
              _infoRow(theme, Icons.battery_std_rounded, 'البطارية', batteryStr),
              _infoRow(theme, Icons.update_rounded, 'آخر تحديث', relativeTime(m['timestamp'] as int? ?? lastMoved)),
              if (lastMoved > 0)
                _infoRow(theme, Icons.person_pin_rounded, 'آخر نشاط', relativeTime(lastMoved)),

              const SizedBox(height: 24),

              // Follow button
              if (!isMe)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _selectMember(key);
                    },
                    icon: const Icon(Icons.my_location_rounded, size: 20),
                    label: Text(_followingMemberId == key ? 'إلغاء التتبع' : 'تتبع العضو'),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const Spacer(),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.end),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════

  Future<void> _loadRoute() async {
    final pts = await FirebaseService.getHistory(
      groupCode: widget.groupCode,
      userId: _fb.userId,
      limit: 300,
    );
    if (!mounted) return;
    setState(
      () => _route = pts
          .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
          .toList(),
    );
  }

  Future<void> _runCleanup() async {
    try {
      await _alertSvc.cleanupExpiredAlerts(widget.groupCode);
    } catch (_) {}
    try {
      await _alertSvc.cleanupExpiredMessages(widget.groupCode);
    } catch (_) {}
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (_fellBackToOsm) return;
    _tileErrors++;
    if (_tileErrors >= 3 && mounted) {
      setState(() {
        _tileUrl = MapboxConfig.osmFallbackTileUrl;
        _fellBackToOsm = true;
      });
    }
  }

  // ═══════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Error state
    if (_error != null) {
      final errorView = MapErrorView(
        message: _error!,
        onRetry: () {
          setState(() => _error = null);
          _initSequence();
        },
      );
      return widget.embedded
          ? errorView
          : Scaffold(appBar: _buildAppBar(), body: errorView);
    }

    // Map content
    final mapBody = Stack(
      children: [
        RepaintBoundary(
          child: FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: MapCameraService.defaultCenter,
              initialZoom: 15.5,
              minZoom: 3,
              maxZoom: 18,
            onMapReady: () {
              _mapReadySafetyTimer?.cancel();
              setState(() => _mapReady = true);
              debugPrint('[Map] onMapReady fired — applying pending camera');
              if (_pendingCamera != null) {
                _mapCtrl.move(_pendingCamera!, _pendingZoom);
                debugPrint('[Map] Camera moved to $_pendingCamera zoom=$_pendingZoom');
              }
            },
              onPositionChanged: (_, hasGesture) {
                if (hasGesture) _userInteracted = true;
              },
              onLongPress: _onLongPress,
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                userAgentPackageName: MapboxConfig.attributionPackage,
                maxNativeZoom: MapboxConfig.maxNativeZoom,
                tileProvider: MapCacheService.tileProvider(_tileUrl),
                errorTileCallback: _onTileError,
              ),
              if (_route.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route,
                      color: theme.colorScheme.secondary.withValues(alpha: 0.5),
                      strokeWidth: 4,
                    ),
                  ],
                ),
              ValueListenableBuilder(
                valueListenable: _alertsNotifier,
                builder: (_, alerts, _) => MarkerLayer(
                  markers: _buildAlertMarkers(),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: _membersNotifier,
                builder: (_, members, _) => MarkerLayer(
                  markers: _buildMemberMarkers(),
                ),
              ),
            ],
          ),
        ),
        // Member selector buttons
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_followingMemberId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FloatingActionButton.extended(
                    heroTag: 'showAll',
                    onPressed: _showAll,
                    icon: const Icon(Icons.group_work_rounded),
                    label: const Text('الكل'),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              FloatingActionButton(
                heroTag: 'pickMember',
                onPressed: _openMemberPicker,
                tooltip: 'اختر عضواً',
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
                child: const Icon(Icons.people_alt_outlined),
              ),
            ],
          ),
        ),
        // OSM banner
        if (_fellBackToOsm && _mapReady)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'OpenStreetMap',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        // Loading overlay — shown until tiles are revealed (first smart camera)
        if (!_tilesRevealed)
          Positioned.fill(
            child: Container(
              color: Colors.black38,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'جارٍ تحضير الخريطة...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'يتم تحميل موقعك',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.embedded) return mapBody;

    return Scaffold(
      appBar: _buildAppBar(),
      body: mapBody,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    title: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.map_rounded,
          size: 22,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        const Text('خريطة المجموعة'),
      ],
    ),
  );

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map_rounded),
          label: 'الخريطة',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline_rounded),
          selectedIcon: Icon(Icons.chat_bubble_rounded),
          label: 'الدردشة',
        ),
        NavigationDestination(
          icon: Icon(Icons.block_outlined),
          selectedIcon: Icon(Icons.block_rounded),
          label: 'القائمة السوداء',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'الإعدادات',
        ),
      ],
      onDestinationSelected: (i) {
        if (i == 1) {
          _navigate(
            ChatScreen(groupCode: widget.groupCode, userName: widget.userName),
          );
        }
        if (i == 2) {
          _navigate(
            BlacklistScreen(
              groupCode: widget.groupCode,
              userName: widget.userName,
            ),
          );
        }
        if (i == 3) {
          _navigate(
            SettingsScreen(
              groupCode: widget.groupCode,
              userName: widget.userName,
            ),
          );
        }
      },
    );
  }

  void _navigate(Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}
