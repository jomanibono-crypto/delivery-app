import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import '../config/mapbox_config.dart';
import '../services/firebase_service.dart';
import '../services/map_cache_service.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';

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

  const MapScreen({
    super.key,
    required this.groupCode,
    required this.userName,
  });

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final MapController _mapController = MapController();

  StreamSubscription<DatabaseEvent>? _membersSubscription;
  bool _cameraInitialized = false;
  bool _mapReady = false;

  // MEMBER SELECTOR: when set, the camera follows this specific member and
  // the auto-fit-all logic is paused. null = normal "show all" mode.
  String? _followingMemberId;

  // Track whether the user has manually interacted with the map (pan/zoom)
  // so we don't yank the camera back during follow mode.
  bool _userInteracted = false;

  // AUDIT-3: tile-failure tracking. After a few consecutive tile errors we
  // switch to the OSM fallback URL so the map isn't blank.
  String _tileUrl = MapboxConfig.mapboxTileUrl;
  int _mapboxTileErrors = 0;
  static const int _maxTileErrorsBeforeFallback = 3;
  bool _fellBackToOsm = false;

  // AUDIT-3: timeout safety. If tiles don't render within 10s, show an error
  // banner instead of an infinite spinner.
  Timer? _loadingTimeout;
  bool _loadingTimedOut = false;

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

  @override
  void initState() {
    super.initState();
    _startLoadingTimeout();
    _listenToMembers();
    _loadHistory();
    _historyRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadHistory();
    });
  }

  // ──────────────────── Loading timeout (AUDIT-3) ────────────────────

  void _startLoadingTimeout() {
    _loadingTimeout?.cancel();
    _loadingTimeout = Timer(const Duration(seconds: 10), () {
      // Only flag a timeout if the camera still hasn't been placed.
      if (!_cameraInitialized && mounted) {
        debugPrint('[Map] Loading timed out after 10s — showing error banner.');
        setState(() => _loadingTimedOut = true);
      }
    });
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
    _membersSubscription =
        _firebaseService.watchGroupMembers(widget.groupCode).listen((event) {
      if (!mounted) return;

      final snap = event.snapshot;
      if (!snap.exists) return;

      final data = snap.value as Map<dynamic, dynamic>?;

      if (data == null) {
        if (mounted) setState(() => _members.clear());
        return;
      }

      final updated = <String, Map<String, dynamic>>{};
      data.forEach((key, value) {
        if (key == '_meta') return;
        if (value is! Map) return;
        final member = value;

        updated[key] = {
          'name': (member['name'] as String?) ?? 'بدون اسم',
          'lat': (member['lat'] as num?)?.toDouble() ?? 0.0,
          'lng': (member['lng'] as num?)?.toDouble() ?? 0.0,
          'online': member['online'] as bool? ?? false,
          'icon': (member['icon'] as String?) ?? '',
          'speed': (member['speed'] as num?)?.toDouble() ?? 0.0,
          'last_moved_at': (member['last_moved_at'] as num?)?.toInt() ?? 0,
        };
      });

      if (!mounted) return;
      setState(() => _members = updated);

      // MEMBER SELECTOR: if following a member, re-center on them as they move.
      // Don't override the camera if the user manually panned/zoomed.
      if (_followingMemberId != null && !_userInteracted) {
        _followMember();
      } else if (_followingMemberId == null) {
        _fitCameraToBounds();
      }
    }, onError: (e) {
      debugPrint('[Map] Members stream error: $e');
    });
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
      _cameraInitialized = true; // dismiss the initial spinner if still showing
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
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            if ((member['icon'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(member['icon'] as String, style: const TextStyle(fontSize: 24)),
              ),
            Flexible(child: Text(name, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(member['online'] as bool ? '🟢 متصل' : '🔴 غير متصل',
                style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
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
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('تتبع'),
          ),
        ],
      ),
    );
  }

  /// Open a thumb-friendly bottom sheet listing all members.
  void _openMemberPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        // Snapshot the members so the list doesn't mutate mid-build.
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
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'اختر عضواً لتتبّعه',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                ),
                const Divider(height: 1),
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
                        leading: CircleAvatar(
                          backgroundColor: isOnline
                              ? Colors.green.shade100
                              : Colors.red.shade50,
                          child: (member['icon'] as String).isNotEmpty
                              ? Text(member['icon'] as String,
                                  style: const TextStyle(fontSize: 22))
                              : const Icon(Icons.person),
                        ),
                        title: Text(
                          '${member['name']}${isMe ? ' (أنت)' : ''}',
                          style: TextStyle(
                            fontWeight: isFollowed
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isFollowed
                                ? const Color(0xFF1565C0)
                                : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          isOnline ? 'متصل' : 'غير متصل',
                          style: TextStyle(
                            fontSize: 12,
                            color: isOnline
                                ? Colors.green.shade700
                                : Colors.red.shade400,
                          ),
                        ),
                        trailing: isFollowed
                            ? const Icon(Icons.my_location,
                                color: Color(0xFF1565C0))
                            : const Icon(Icons.chevron_right,
                                color: Colors.grey),
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

    if (!_cameraInitialized || force || _members.length >= 3) {
      _mapController.move(center, zoom);
      _loadingTimeout?.cancel();
      setState(() {
        _cameraInitialized = true;
        _loadingTimedOut = false;
      });
    }
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
      final color = isFollowed ? const Color(0xFF1565C0) : _memberColors[colorIndex];
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
                      width: isFollowed ? 38 : 32,
                      height: isFollowed ? 38 : 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    (member['icon'] as String).isNotEmpty
                        ? Text(
                            member['icon'] as String,
                            style: const TextStyle(fontSize: 18),
                          )
                        : const Icon(Icons.person, color: Colors.white, size: 20),
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

  // ──────────────────── Lifecycle ────────────────────

  @override
  void dispose() {
    _loadingTimeout?.cancel();
    _membersSubscription?.cancel();
    _historyRefreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ──────────────────── Build ────────────────────

  @override
  Widget build(BuildContext context) {
    // The bottom navigation bar's height (~80px). Buttons sit above it in the
    // thumb-friendly zone.
    const bottomNavHeight = 80.0;
    const buttonSpacing = 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('خريطة المجموعة'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.group, size: 16),
                label: Text('${_members.length} أعضاء'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: _members.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'في انتظار الأعضاء...',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
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
                    // MEMBER SELECTOR: detect manual pan/zoom so we don't
                    // yank the camera during follow mode.
                    onPositionChanged: (position, hasGesture) {
                      if (hasGesture) {
                        _userInteracted = true;
                      }
                    },
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
                            color: const Color(0xFF1565C0).withOpacity(0.5),
                            strokeWidth: 4,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: _buildMarkers()),
                  ],
                ),

                // ──────────────────────────────────────────────────────
                // MEMBER SELECTOR BUTTONS — lower thumb-friendly zone
                // Positioned ~16px above the bottom nav bar (~80px tall),
                // so ~96px from the very bottom. Right-aligned for right-thumb.
                // ──────────────────────────────────────────────────────
                Positioned(
                  right: 16,
                  bottom: buttonSpacing,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // "Show all" button — only visible while following someone.
                      if (_followingMemberId != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FloatingActionButton.extended(
                            heroTag: 'showAllBtn',
                            onPressed: _showAllMembers,
                            icon: const Icon(Icons.group_work),
                            label: const Text('الكل'),
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      // Member selector button (always visible when members exist).
                      FloatingActionButton(
                        heroTag: 'memberPickerBtn',
                        onPressed: _openMemberPicker,
                        tooltip: 'اختر عضواً',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1565C0),
                        child: const Icon(Icons.people_alt_outlined),
                      ),
                    ],
                  ),
                ),

                // Initial-loading spinner overlay.
                if (!_cameraInitialized && !_loadingTimedOut)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.white54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text(
                              'جاري تحميل الخريطة...',
                              style: TextStyle(
                                color: Color(0xFF1565C0),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Timeout error banner.
                if (_loadingTimedOut)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.grey.shade100,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off,
                                  size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text(
                                'تعذّر تحميل الخريطة، تحقق من الإنترنت',
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _loadingTimedOut = false;
                                    _cameraInitialized = false;
                                    _fellBackToOsm = true;
                                    _tileUrl =
                                        MapboxConfig.osmFallbackTileUrl;
                                  });
                                  _startLoadingTimeout();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // OSM fallback indicator.
                if (_fellBackToOsm && _cameraInitialized)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
        NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'الخريطة'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'الدردشة'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
      ],
      onDestinationSelected: (index) {
        if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(groupCode: widget.groupCode, userName: widget.userName)));
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SettingsScreen(groupCode: widget.groupCode, userName: widget.userName)));
        }
      },
    );
  }
}
