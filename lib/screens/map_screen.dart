import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import '../config/mapbox_config.dart';
import '../services/firebase_service.dart';
import '../services/map_cache_service.dart';
import '../services/alert_service.dart';
import '../widgets/vote_widget.dart';
import '../utils/relative_time.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'blacklist_screen.dart';

/// Map screen showing all group members as colored markers.
///
/// Tile source: tries Mapbox first, and automatically falls back to OpenStreetMap
/// if Mapbox tiles fail (invalid token, rate limit, network). This guarantees the
/// map background always renders — it never gets stuck on a loading spinner.
///
/// MEMBER SELECTOR (follow mode): the user can pick a member from a bottom sheet
/// to follow — the camera smoothly tracks that member's live position. A second
/// button returns to "show all" mode. Both buttons sit in the lower thumb zone.
class MapScreen extends StatefulWidget {
  final String groupCode;
  final String userName;

  const MapScreen({super.key, required this.groupCode, required this.userName});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final MapController _mapController = MapController();

  StreamSubscription<DatabaseEvent>? _membersSubscription;
  bool _mapReady = false;

  // MEMBER SELECTOR: when set, the camera follows this specific member and
  // the auto-fit-all logic is paused. null = normal "show all" mode.
  String? _followingMemberId;

  // Track whether the user has manually interacted with the map (pan/zoom)
  // so we don't yank the camera back during follow mode.
  bool _userInteracted = false;

  // ── Initial location state (Feature 1) ──
  // Set to true once we have a location to show (last known OR GPS).
  // Until true, only the loading screen is visible.
  bool _initialLocationReady = false;

  // True once the smart-camera logic has run (Feature 2).
  bool _firstLocationReceived = false;

  // 2-second timer that triggers the group-fit animation (Feature 2).
  Timer? _smartCameraTimer;

  // AUDIT-3: tile-failure tracking. After a few consecutive tile errors we
  // switch to the OSM fallback URL so the map isn't blank.
  String _tileUrl = MapboxConfig.mapboxTileUrl;
  int _mapboxTileErrors = 0;
  static const int _maxTileErrorsBeforeFallback = 3;
  bool _fellBackToOsm = false;

  // All current members from Firebase: { userId: { name, lat, lng, online, icon } }
  Map<String, Map<String, dynamic>> _members = {};

  // Route history: polyline points for the current user's path.
  List<LatLng> _routePoints = [];
  Timer? _historyRefreshTimer;

  // A unique color per member so every marker is visually distinguishable.
  // Index 0 is reserved for the current user (blue).
  static const List<Color> _memberColors = [
    Color(0xFF1565C0), // Blue  – current user
    Color(0xFFE53935), // Red
    Color(0xFF43A047), // Green
    Color(0xFFFB8C00), // Orange
    Color(0xFF8E24AA), // Purple
    Color(0xFF00ACC1), // Cyan
    Color(0xFFD81B60), // Pink
  ];

  final AlertService _alertService = AlertService();
  List<AlertData> _alerts = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _listenToMembers();
    _loadHistory();
    _historyRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadHistory();
    });
    _listenToAlerts();
    _runCleanup();
    // Alert notifications are handled globally by AlertNotificationService
  }

  @override
  void dispose() {
    _membersSubscription?.cancel();
    _historyRefreshTimer?.cancel();
    _smartCameraTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ──────────────────── Tile error fallback (AUDIT-3) ────────────────────

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (_fellBackToOsm) return; // already on fallback
    _mapboxTileErrors++;
    debugPrint('[Map] Tile error #$_mapboxTileErrors: $error');
    if (_mapboxTileErrors >= _maxTileErrorsBeforeFallback && mounted) {
      debugPrint('[Map] Switching to OpenStreetMap fallback tiles.');
      setState(() {
        _tileUrl = MapboxConfig.osmFallbackTileUrl;
        _fellBackToOsm = true;
      });
    }
  }

  // ──────────────────── Alerts ────────────────────

  void _listenToAlerts() {
    _alertService.watchAlerts(widget.groupCode).listen((alerts) {
      if (!mounted) return;
      setState(() {
        _alerts = alerts.where((a) => !a.resolved).toList();
      });
    });
  }

  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    _showAlertContextMenu(point);
  }

  void _showAlertContextMenu(LatLng point) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
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
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'اختر نوع التنبيه',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _alertOption(
                    ctx,
                    point,
                    AlertType.police,
                    Icons.local_police_rounded,
                    'شرطة',
                    'نقطة تفتيش شرطة في هذا الموقع',
                  ),
                  const SizedBox(height: 10),
                  _alertOption(
                    ctx,
                    point,
                    AlertType.speedTrap,
                    Icons.speed_rounded,
                    'رادار',
                    'كاميرا سرعة أو رادار مرور',
                  ),
                  const SizedBox(height: 10),
                  _alertOption(
                    ctx,
                    point,
                    AlertType.control,
                    Icons.supervisor_account_rounded,
                    'مراقب غلوفو',
                    'مراقب تابع لغلوفو في المنطقة',
                  ),
                  const SizedBox(height: 10),
                  _alertOption(
                    ctx,
                    point,
                    AlertType.note,
                    Icons.sticky_note_2_rounded,
                    'ملاحظة',
                    'نص يظهر في الموقع على الخريطة',
                  ),
                  const SizedBox(height: 10),
                  _alertOption(
                    ctx,
                    point,
                    AlertType.badCustomer,
                    Icons.person_off_rounded,
                    'عميل سيء',
                    'تسجيل عميل رفض الدفع أو سبب آخر',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNoteDialog(LatLng point, AlertType type) {
    final theme = Theme.of(context);
    final noteController = TextEditingController();
    final reasonController = TextEditingController();
    final isBad = type == AlertType.badCustomer;
    final isNote = type == AlertType.note;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return Directionality(
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
                      color: type.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      type == AlertType.police
                          ? Icons.local_police_rounded
                          : type == AlertType.speedTrap
                          ? Icons.speed_rounded
                          : type == AlertType.control
                          ? Icons.supervisor_account_rounded
                          : type == AlertType.note
                          ? Icons.sticky_note_2_rounded
                          : Icons.person_off_rounded,
                      color: type.color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(type.label, style: theme.textTheme.titleLarge),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBad)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: reasonController,
                        textDirection: TextDirection.rtl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: '* السبب',
                          hintText: 'مثال: رفض الدفع، سلوك غير لائق...',
                        ),
                        onChanged: (_) => setDlgState(() {}),
                      ),
                    ),
                  TextField(
                    controller: noteController,
                    textDirection: TextDirection.rtl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: isBad
                          ? 'ملاحظة إضافية (اختياري)'
                          : (isNote
                                ? 'اكتب ملاحظتك...'
                                : 'ملاحظة إضافية (اختياري)'),
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (isBad && reasonController.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    await _alertService.addAlert(
                      groupCode: widget.groupCode,
                      type: type,
                      lat: point.latitude,
                      lng: point.longitude,
                      note: noteController.text.trim(),
                      reason: reasonController.text.trim(),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${type.label}: ${isNote ? 'تمت الإضافة' : 'تم الإبلاغ'}',
                            textAlign: TextAlign.right,
                          ),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                          backgroundColor: type.color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(isBad ? 'تأكيد' : 'تأكيد'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _alertOption(
    BuildContext ctx,
    LatLng point,
    AlertType type,
    IconData icon,
    String title,
    String desc,
  ) {
    final theme = Theme.of(ctx);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: type.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pop(ctx);
            _showNoteDialog(point, type);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: type.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: type.color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_left_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runCleanup() async {
    try {
      final deleted = await _alertService.cleanupExpiredAlerts(
        widget.groupCode,
      );
      final msgDeleted = await _alertService.cleanupExpiredMessages(
        widget.groupCode,
      );
      if (deleted > 0 || msgDeleted > 0) {
        debugPrint(
          '[MapCleanup] Expired: $deleted alerts, $msgDeleted messages',
        );
      }
    } catch (_) {}
  }

  // ──────────────────── Camera Initialization ────────────────────

  void _initCamera() async {
    try {
      // 1. Try last known position (instant, no GPS needed)
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        final target = LatLng(lastPos.latitude, lastPos.longitude);
        _mapController.move(target, 16);
        if (mounted) setState(() => _initialLocationReady = true);
        _firstLocationReceived = true;
        debugPrint('[Map] Last known location: $target');
        return;
      }
    } catch (_) {
      // Ignore — fall through to GPS
    }

    // 2. No cached location — request current GPS position directly.
    //    This prevents the loading screen from hanging forever waiting
    //    for Firebase data that may arrive slowly or never.
    if (!mounted) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).timeout(const Duration(seconds: 8));
      if (mounted) {
        final target = LatLng(pos.latitude, pos.longitude);
        _mapController.move(target, 16);
        setState(() => _initialLocationReady = true);
        _firstLocationReceived = true;
        debugPrint('[Map] GPS position obtained directly: $target');
        return;
      }
    } catch (_) {
      // GPS failed — fall through to Agadir default
    }

    // 3. Fallback: show the map with the Agadir default so the user
    //    never gets stuck on a loading screen. Firebase data will
    //    update the camera when it arrives (see _listenToMembers).
    if (mounted) {
      setState(() => _initialLocationReady = true);
      debugPrint('[Map] No position available — showing Agadir fallback');
    }
  }

  // ──────────────────── Loading Screen (Feature 1) ────────────────────

  Widget _buildLocationLoadingScreen() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.my_location_rounded,
              size: 44,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'جارٍ تحديد موقعك...',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────── Route History ────────────────────

  Future<void> _loadHistory() async {
    final userId = _firebaseService.userId;
    final points = await FirebaseService.getHistory(
      groupCode: widget.groupCode,
      userId: userId,
      limit: 300,
    );
    if (!mounted) return;
    setState(() {
      _routePoints = points
          .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
          .toList();
    });
  }

  // ──────────────────── Firebase Listener ────────────────────

  void _listenToMembers() {
    _membersSubscription = _firebaseService
        .watchGroupMembers(widget.groupCode)
        .listen(
          (event) {
            if (!mounted) return;

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
              if (key == '_meta' || key == '_chat' || key == '_alerts') return;
              if (value is! Map) return;
              final member = value;

              updated[key] = {
                'name': (member['name'] as String?) ?? 'بدون اسم',
                'lat': (member['lat'] as num?)?.toDouble() ?? 0.0,
                'lng': (member['lng'] as num?)?.toDouble() ?? 0.0,
                'online': member['online'] as bool? ?? false,
                'icon': (member['icon'] as String?) ?? '',
                'speed': (member['speed'] as num?)?.toDouble() ?? 0.0,
                'last_moved_at':
                    (member['last_moved_at'] as num?)?.toInt() ?? 0,
              };
            });

            if (!mounted) return;
            setState(() => _members = updated);

            // Feature 1: if no location is ready yet, use the first valid
            // GPS coordinate from Firebase to reveal the map.
            if (!_initialLocationReady && _mapReady) {
              final uid = _firebaseService.userId;
              final myData = updated[uid];
              if (myData != null) {
                final myLat = myData['lat'] as double? ?? 0.0;
                final myLng = myData['lng'] as double? ?? 0.0;
                if (myLat != 0.0 && myLng != 0.0) {
                  _mapController.move(LatLng(myLat, myLng), 16);
                  if (mounted) setState(() => _initialLocationReady = true);
                  _firstLocationReceived = true;
                  debugPrint(
                    '[Map] GPS location received — map revealed at ($myLat, $myLng)',
                  );
                }
              }
            }

            // Feature 2: smart camera — only once, after the map is visible
            // and we have a valid user position.
            if (!_firstLocationReceived &&
                !_userInteracted &&
                _mapReady &&
                _initialLocationReady) {
              final uid = _firebaseService.userId;
              final myData = updated[uid];
              if (myData != null) {
                final myLat = myData['lat'] as double? ?? 0.0;
                final myLng = myData['lng'] as double? ?? 0.0;
                if (myLat != 0.0 && myLng != 0.0) {
                  _firstLocationReceived = true;
                  final myPos = LatLng(myLat, myLng);

                  // Count other members (exclude self and null-coordinate entries)
                  final others = updated.entries.where((e) {
                    if (e.key == uid) return false;
                    final lat = (e.value['lat'] as double?) ?? 0.0;
                    final lng = (e.value['lng'] as double?) ?? 0.0;
                    return lat != 0.0 && lng != 0.0;
                  }).toList();

                  if (others.isEmpty) {
                    // Case A: alone — center on me at zoom 16
                    _mapController.move(myPos, 16);
                    debugPrint(
                      '[Map] Smart camera — alone, centered at zoom 16',
                    );
                  } else {
                    // Case B: others exist — center on me first, then expand
                    _mapController.move(myPos, 16);
                    _smartCameraTimer?.cancel();
                    _smartCameraTimer = Timer(const Duration(seconds: 2), () {
                      if (!mounted) return;
                      _fitCameraToBounds(force: true);
                      debugPrint(
                        '[Map] Smart camera — expanded to show ${others.length + 1} members',
                      );
                    });
                  }
                }
              }
            }

            // MEMBER SELECTOR: if following a member, re-center on them as they move.
            // Don't override the camera if the user manually panned/zoomed.
            if (_followingMemberId != null && !_userInteracted) {
              _followMember();
            } else if (_followingMemberId == null) {
              _fitCameraToBounds();
            }
          },
          onError: (e) {
            debugPrint('[Map] Members stream error: $e');
          },
        );
  }

  // ──────────────────── MEMBER SELECTOR ────────────────────

  /// Smoothly move + zoom in on the currently-followed member.
  void _followMember() {
    if (!_mapReady || _followingMemberId == null) return;
    final member = _members[_followingMemberId];
    if (member == null) return;

    final target = LatLng(member['lat'] as double, member['lng'] as double);
    // Zoom 17 = street-level, close enough to see the member clearly.
    _mapController.move(target, 17);
  }

  /// Start following a specific member. Pauses auto-fit-all.
  void _selectMember(String memberId) {
    setState(() {
      _followingMemberId = memberId;
      _userInteracted = false; // reset manual-interaction flag
      _initialLocationReady =
          true; // dismiss the initial spinner if still showing
    });
    _followMember();
  }

  /// Exit follow mode → return to auto-fit-all-members.
  void _showAllMembers() {
    setState(() {
      _followingMemberId = null;
      _userInteracted = false;
    });
    _fitCameraToBounds(force: true);
  }

  /// Show a popup with the member's speed or idle duration.
  void _showMemberPopup(String memberId) {
    final theme = Theme.of(context);
    final member = _members[memberId];
    if (member == null) return;
    final isMe = memberId == _firebaseService.userId;
    final name = '${member['name']}${isMe ? ' (أنت)' : ''}';
    final speed = member['speed'] as double;
    final lastMovedAt = member['last_moved_at'] as int;

    String status;
    if (speed > 0) {
      final speedKmh = (speed * 3.6).toStringAsFixed(1);
      status = '🚶 يتحرك بسرعة $speedKmh كم/س';
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      final idleMs = now - lastMovedAt;
      if (lastMovedAt <= 0 || idleMs < 0 || idleMs > 86400000) {
        status = '⏸ متوقف';
      } else {
        final idleMinutes = idleMs ~/ 60000;
        if (idleMinutes < 1) {
          status = '⏸ متوقف منذ لحظات';
        } else if (idleMinutes < 60) {
          status = '⏸ متوقف منذ $idleMinutes دقائق';
        } else {
          final hours = idleMinutes ~/ 60;
          final mins = idleMinutes % 60;
          status = '⏸ متوقف منذ $hours س و $mins د';
        }
      }
    }

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
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: (member['icon'] as String).isNotEmpty
                      ? Text(
                          member['icon'] as String,
                          style: const TextStyle(fontSize: 22),
                        )
                      : Icon(
                          Icons.person_rounded,
                          color: theme.colorScheme.primary,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: theme.textTheme.titleLarge)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(status, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: member['online'] as bool
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    member['online'] as bool ? 'متصل' : 'غير متصل',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _selectMember(memberId);
              },
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('تتبع'),
            ),
          ],
        ),
      ),
    );
  }

  void _openMemberPicker() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final entries = _members.entries.toList();
        final userId = _firebaseService.userId;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.55,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'اختر عضواً لتتبّعه',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final entry = entries[i];
                      final member = entry.value;
                      final isMe = entry.key == userId;
                      final isFollowed = entry.key == _followingMemberId;
                      final isOnline = member['online'] == true;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 2,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? theme.colorScheme.tertiaryContainer
                                : theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: (member['icon'] as String).isNotEmpty
                                ? Text(
                                    member['icon'] as String,
                                    style: const TextStyle(fontSize: 22),
                                  )
                                : Icon(
                                    Icons.person_rounded,
                                    color: isOnline
                                        ? theme.colorScheme.tertiary
                                        : theme.colorScheme.error,
                                    size: 22,
                                  ),
                          ),
                        ),
                        title: Text(
                          '${member['name']}${isMe ? ' (أنت)' : ''}',
                          style: TextStyle(
                            fontWeight: isFollowed
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isFollowed
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          isOnline ? 'متصل' : 'غير متصل',
                          style: TextStyle(
                            fontSize: 12,
                            color: isOnline
                                ? theme.colorScheme.tertiary
                                : theme.colorScheme.error,
                          ),
                        ),
                        trailing: isFollowed
                            ? Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.my_location_rounded,
                                  color: theme.colorScheme.primary,
                                  size: 18,
                                ),
                              )
                            : Icon(
                                Icons.chevron_left_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _selectMember(entry.key);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────────────── Camera ────────────────────

  /// Fit the map to show all members' markers.
  /// [force] bypasses the "already initialized" guard (used when exiting
  /// follow mode to re-show everyone).
  void _fitCameraToBounds({bool force = false}) {
    if (!_mapReady) return;
    if (_members.isEmpty) return;
    // MEMBER SELECTOR: never auto-fit while following someone.
    if (_followingMemberId != null) return;

    final positions = _members.values
        .map((m) => LatLng(m['lat'] as double, m['lng'] as double))
        .toList();
    if (positions.isEmpty) return;

    LatLng center;
    double zoom;

    if (positions.length == 1) {
      center = positions.first;
      zoom = 15;
    } else {
      double minLat = positions.first.latitude;
      double maxLat = positions.first.latitude;
      double minLng = positions.first.longitude;
      double maxLng = positions.first.longitude;

      for (final p in positions) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      final span = ((maxLat - minLat).abs() > (maxLng - minLng).abs())
          ? (maxLat - minLat).abs()
          : (maxLng - minLng).abs();
      if (span > 0.1) {
        zoom = 10;
      } else if (span > 0.05) {
        zoom = 12;
      } else if (span > 0.01) {
        zoom = 14;
      } else {
        zoom = 16;
      }
    }

    if (_mapReady && (force || _members.length >= 3)) {
      _mapController.move(center, zoom);
    }
  }

  List<Marker> _buildAlertMarkers() {
    return _alerts.map((alert) {
      IconData icon;
      switch (alert.type) {
        case AlertType.police:
          icon = Icons.local_police_rounded;
          break;
        case AlertType.speedTrap:
          icon = Icons.speed_rounded;
          break;
        case AlertType.control:
          icon = Icons.supervisor_account_rounded;
          break;
        case AlertType.note:
          icon = Icons.sticky_note_2_rounded;
          break;
        case AlertType.hazard:
          icon = Icons.warning_rounded;
          break;
        case AlertType.accident:
          icon = Icons.car_crash_rounded;
          break;
        case AlertType.badCustomer:
          icon = Icons.person_off_rounded;
          break;
      }

      final markerHeight = alert.note.isNotEmpty ? 88.0 : 56.0;

      return Marker(
        point: LatLng(alert.lat, alert.lng),
        width: 160,
        height: markerHeight,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => _showAlertDetail(alert),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
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
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.red.shade300,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 10,
                        color: Colors.red.shade300,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: alert.type.color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  alert.type.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (alert.note.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  constraints: const BoxConstraints(maxWidth: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: Text(
                    alert.note,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF1C1B1F),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _showAlertDetail(AlertData alert) {
    final theme = Theme.of(context);
    final userId = FirebaseService().userId;
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
                  _alertTypeIcon(alert.type),
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
                currentUserId: userId,
                onVote: (vote) async {
                  await _alertService.submitVote(
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

  IconData _alertTypeIcon(AlertType type) {
    switch (type) {
      case AlertType.police:
        return Icons.local_police_rounded;
      case AlertType.speedTrap:
        return Icons.speed_rounded;
      case AlertType.control:
        return Icons.supervisor_account_rounded;
      case AlertType.hazard:
        return Icons.warning_rounded;
      case AlertType.accident:
        return Icons.car_crash_rounded;
      case AlertType.note:
        return Icons.sticky_note_2_rounded;
      case AlertType.badCustomer:
        return Icons.person_off_rounded;
    }
  }

  void _confirmDeleteAlert(AlertData alert) {
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text('هل أنت متأكد؟', style: theme.textTheme.titleLarge),
            ],
          ),
          content: Text(
            'سيتم حذف ${alert.type.label} من الخريطة',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لا'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _alertService.deleteAlert(widget.groupCode, alert.id);
              },
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              child: const Text('نعم، احذف'),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────── Markers ────────────────────

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    final userId = _firebaseService.userId;
    final memberKeys = _members.keys.toList();

    for (int i = 0; i < memberKeys.length; i++) {
      final key = memberKeys[i];
      final member = _members[key]!;
      final lat = member['lat'] as double;
      final lng = member['lng'] as double;
      final isMe = key == userId;
      final isFollowed = key == _followingMemberId;
      final colorIndex = isMe ? 0 : (i % (_memberColors.length - 1)) + 1;
      final color = isFollowed
          ? const Color(0xFFFF9800)
          : _memberColors[colorIndex];
      final displayName = '${member['name']}${isMe ? ' (أنت)' : ''}';

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 80,
          height: 64,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _showMemberPopup(key),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: isFollowed ? 40 : 32,
                      height: isFollowed ? 40 : 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isFollowed
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    (member['icon'] as String).isNotEmpty
                        ? Text(
                            member['icon'] as String,
                            style: const TextStyle(fontSize: 16),
                          )
                        : Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  // ──────────────────── Build ────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const buttonSpacing = 16.0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_rounded, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('خريطة المجموعة'),
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
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_rounded,
                      size: 16,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_members.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: !_initialLocationReady
          ? _buildLocationLoadingScreen()
          : _members.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.map_outlined,
                      size: 36,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'في انتظار الأعضاء...',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(33.97, -6.85),
                    initialZoom: 13,
                    minZoom: 3,
                    maxZoom: 18,
                    onMapReady: () {
                      debugPrint('[Map] onMapReady fired.');
                      setState(() => _mapReady = true);
                      _fitCameraToBounds();
                    },
                    onPositionChanged: (position, hasGesture) {
                      if (hasGesture) {
                        _userInteracted = true;
                      }
                    },
                    onLongPress: (tapPosition, point) =>
                        _onMapLongPress(tapPosition, point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl,
                      userAgentPackageName: MapboxConfig.attributionPackage,
                      maxNativeZoom: MapboxConfig.maxNativeZoom,
                      tileProvider: MapCacheService.tileProvider(_tileUrl),
                      errorTileCallback: _onTileError,
                    ),
                    if (_routePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            color: theme.colorScheme.secondary.withValues(
                              alpha: 0.5,
                            ),
                            strokeWidth: 4,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: _buildAlertMarkers()),
                    MarkerLayer(markers: _buildMarkers()),
                  ],
                ),

                // MEMBER SELECTOR BUTTONS
                Positioned(
                  right: 16,
                  bottom: buttonSpacing,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_followingMemberId != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FloatingActionButton.extended(
                            heroTag: 'showAllBtn',
                            onPressed: _showAllMembers,
                            icon: const Icon(Icons.group_work_rounded),
                            label: const Text('الكل'),
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      FloatingActionButton(
                        heroTag: 'memberPickerBtn',
                        onPressed: _openMemberPicker,
                        tooltip: 'اختر عضواً',
                        backgroundColor: Colors.white,
                        foregroundColor: theme.colorScheme.primary,
                        child: const Icon(Icons.people_alt_outlined),
                      ),
                    ],
                  ),
                ),

                // OSM fallback indicator.
                if (_fellBackToOsm && _mapReady)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'OSM',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

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
      onDestinationSelected: (index) {
        if (index == 1) {
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
