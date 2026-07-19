import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/status_pill.dart';
import '../config/mapbox_config.dart';
import '../services/firebase_service.dart';
import '../services/blacklist_service.dart';
import '../services/map_cache_service.dart';
import '../services/alert_service.dart';
import '../services/map_location_service.dart';
import '../services/map_camera_service.dart';
import '../services/foreground_screen_service.dart';
import '../widgets/vote_widget.dart';
import '../widgets/map_error_view.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/info_row.dart';
import '../utils/relative_time.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'blacklist_screen.dart';
import 'member_detail_screen.dart';

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
  final BlacklistService _blacklistSvc = BlacklistService();
  final MapLocationService _locationSvc = MapLocationService();
  final MapController _mapCtrl = MapController();

  // ── Subscriptions ──
  StreamSubscription<DatabaseEvent>? _membersSub;
  StreamSubscription<List<AlertData>>? _alertsSub;
  StreamSubscription<List<BlacklistEntry>>? _badCustomerSub;
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
  final ValueNotifier<List<BlacklistEntry>> _badCustomerNotifier =
      ValueNotifier([]);
  Map<String, Map<String, dynamic>> get _members => _membersNotifier.value;
  List<AlertData> get _alerts => _alertsNotifier.value;
  List<BlacklistEntry> get _badCustomers => _badCustomerNotifier.value;

  List<LatLng> _route = [];
  String? _followingMemberId;

  // ── Marker colors (matches new design mockup) ──
  // me = orange, others = indigo/mint/rose/amber rotation
  static const _colors = [
    Color(0xFFFF7A45), // me — orange (followed = highlighted orange)
    Color(0xFF5B6CFF), // indigo
    Color(0xFF00D4A0), // mint
    Color(0xFFFF4D6D), // rose
    Color(0xFFFFB627), // amber
    Color(0xFF8E24AA), // purple
    Color(0xFF00ACC1), // cyan
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.embedded) {
      ForegroundScreenService().set(ForegroundScreen.map);
    }
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
    if (!widget.embedded) {
      ForegroundScreenService().clear(ForegroundScreen.map);
    }
    _membersSub?.cancel();
    _alertsSub?.cancel();
    _badCustomerSub?.cancel();
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
      _listenBadCustomers();
      debugPrint('[Map] Bad-customer listener started');

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

  void _listenBadCustomers() {
    _badCustomerSub = _blacklistSvc.watchMarkers().listen((entries) {
      if (!mounted) return;
      _badCustomerNotifier.value = entries;
    }, onError: (e) {
      debugPrint('[Map] Bad-customer marker stream error: $e');
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

  /// Long-press menu. Top section: ephemeral alert types. Bottom section:
  /// a single "permanent bad customer" tile that drops a persistent marker.
  void _showAlertContextMenu(LatLng point) {
    AppBottomSheet.show<void>(
      context,
      title: 'إبلاغ عن',
      subtitle: 'اختر نوع البلاغ أو أضف علامة دائمة',
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AlertComposerGrid(
            onSelect: (type) async {
              await _alertSvc.addAlert(
                groupCode: widget.groupCode,
                type: type,
                lat: point.latitude,
                lng: point.longitude,
              );
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم الإبلاغ عن ${type.label}'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const _SheetSectionLabel(text: 'علامات دائمة'),
          Material(
            color: AppColors.danger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                _showBadCustomerComposer(point);
              },
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_off_rounded,
                        color: AppColors.danger,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text(
                        'زبون سيئ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink900,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.danger.withValues(alpha: 0.4),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Composer for dropping a persistent bad-customer marker at [point].
  /// All fields optional — a tap on "حفظ العلامة" with everything empty still
  /// creates a marker (carries only coordinates + audit info).
  void _showBadCustomerComposer(LatLng point) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool saving = false;

    AppBottomSheet.show<void>(
      context,
      title: 'زبون سيئ',
      subtitle: 'العلامة ستبقى على الخريطة حتى يتم حذفها يدوياً',
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      child: StatefulBuilder(
        builder: (ctx, setLocal) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppInput(
                controller: nameCtrl,
                label: 'اسم الزبون (اختياري)',
                hint: 'مثال: محمد',
                leadingIcon: Icons.person_rounded,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: AppSpacing.md),
              AppInput(
                controller: phoneCtrl,
                label: 'رقم الهاتف (اختياري)',
                hint: '06xxxxxxxx',
                leadingIcon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: AppSpacing.md),
              AppInput(
                controller: reasonCtrl,
                label: 'السبب (اختياري)',
                hint: 'لماذا هذا الزبون سيئ؟',
                leadingIcon: Icons.note_rounded,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'حفظ العلامة',
                leadingIcon: Icons.push_pin_rounded,
                isLoading: saving,
                onPressed: () async {
                  setLocal(() => saving = true);
                  try {
                    await _blacklistSvc.addEntry(
                      lat: point.latitude,
                      lng: point.longitude,
                      name: nameCtrl.text,
                      phone: phoneCtrl.text,
                      reason: reasonCtrl.text,
                    );
                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('تمت إضافة علامة زبون سيئ'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تعذّر حفظ العلامة: $e'),
                          backgroundColor: AppColors.danger,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setLocal(() => saving = false);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// Detail sheet for a persistent bad-customer marker. Shows whatever
  /// metadata the entry carries and a delete button.
  void _showBadCustomerDetail(BlacklistEntry entry) {
    AppBottomSheet.show<void>(
      context,
      title: 'زبون سيئ',
      subtitle: 'علامة دائمة على الخريطة',
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                gradient: AppColors.dangerGradient,
                shape: BoxShape.circle,
                boxShadow: AppColors.shadowGlowDanger,
              ),
              child: const Icon(
                Icons.person_off_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (entry.name != null && entry.name!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InfoRow(
                icon: Icons.person_rounded,
                label: 'الاسم',
                value: entry.name!,
              ),
            ),
          if (entry.phone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InfoRow(
                icon: Icons.phone_rounded,
                label: 'الهاتف',
                value: entry.phone,
              ),
            ),
          if (entry.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InfoRow(
                icon: Icons.note_rounded,
                label: 'السبب',
                value: entry.reason,
              ),
            ),
          InfoRow(
            icon: Icons.person_pin_rounded,
            label: 'أضيفت بواسطة',
            value: entry.addedByName,
          ),
          if (entry.timestamp > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoRow(
              icon: Icons.schedule_rounded,
              label: 'التاريخ',
              value: relativeTime(entry.timestamp),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'حذف العلامة',
            variant: AppButtonVariant.danger,
            leadingIcon: Icons.delete_outline_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              _confirmDeleteBadCustomer(entry);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBadCustomer(BlacklistEntry entry) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('حذف العلامة'),
          content: const Text(
            'هل تريد حذف هذه العلامة نهائياً؟ لا يمكن التراجع.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _blacklistSvc.deleteEntry(entry.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('تم حذف العلامة'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('حذف'),
            ),
          ],
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

  List<Marker> _buildBadCustomerMarkers() {
    return _badCustomers.map((entry) {
      return Marker(
        point: LatLng(entry.lat!, entry.lng!),
        width: 110,
        height: 70,
        child: GestureDetector(
          onTap: () => _showBadCustomerDetail(entry),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.dangerGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_off_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'زبون سيئ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
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
            onTap: () => _openMemberDetails(key),
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
                  width: isMe ? 40 : 36,
                  height: isMe ? 40 : 36,
                  decoration: BoxDecoration(
                    gradient: isMe
                        ? const LinearGradient(
                            colors: [Color(0xFFFF7A45), Color(0xFFF25A1F)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isMe ? null : color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: isMe ? 3 : 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isMe
                            ? const Color(0xFFFF7A45).withValues(alpha: 0.5)
                            : Colors.black.withValues(alpha: 0.3),
                        blurRadius: isMe ? 12 : 4,
                        spreadRadius: isMe ? 2 : 0,
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

  /// Navigate to the dedicated Member Details screen with Hero animation
  /// matching mockup Screen 7 (gradient header + stats grid).
  void _openMemberDetails(String key) {
    final m = _members[key];
    if (m == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => MemberDetailScreen(
          memberId: key,
          memberData: m,
          allMembers: _members,
          currentUserId: _fb.userId,
          onFollow: _selectMember,
        ),
        transitionsBuilder: (_, anim, _, child) {
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: anim,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
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
          : Scaffold(
              backgroundColor: AppColors.ink800,
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    if (!widget.embedded) _buildMapTopBar(),
                    Expanded(child: errorView),
                  ],
                ),
              ),
              bottomNavigationBar:
                  widget.embedded ? null : _buildBottomNav(),
            );
    }

    // Map content
    final mapBody = Stack(
      children: [
        // Map (dark background to avoid white flash before tiles load)
        Container(color: AppColors.ink800),
        FlutterMap(
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
                    color: AppColors.orange500.withValues(alpha: 0.85),
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
            ValueListenableBuilder<List<BlacklistEntry>>(
              valueListenable: _badCustomerNotifier,
              builder: (_, entries, _) => MarkerLayer(
                markers: _buildBadCustomerMarkers(),
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

        // Top glass bar (status + group code)
        if (!widget.embedded) _buildMapTopBar(),

        // Members floating card
        if (_members.isNotEmpty) _buildMembersCard(),

        // FABs
        Positioned(
          right: AppSpacing.lg,
          bottom: widget.embedded
              ? AppSpacing.huge
              : AppSpacing.huge * 2.5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_followingMemberId != null) ...[
                _MapFab(
                  icon: Icons.group_work_rounded,
                  onPressed: _showAll,
                  extended: 'الكل',
                  variant: _FabVariant.primary,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              _MapFab(
                icon: Icons.people_alt_outlined,
                onPressed: _openMemberPicker,
                variant: _FabVariant.secondary,
              ),
            ],
          ),
        ),

        // OSM banner
        if (_fellBackToOsm && _mapReady)
          Positioned(
            top: AppSpacing.lg,
            left: AppSpacing.lg,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Text(
                'OpenStreetMap',
                style: AppTypography.labelSm.copyWith(color: Colors.white),
              ),
            ),
          ),

        // Loading overlay
        if (!_tilesRevealed) _buildLoadingOverlay(),
      ],
    );

    if (widget.embedded) return mapBody;

    return Scaffold(
      backgroundColor: AppColors.ink800,
      extendBody: true,
      body: mapBody,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildMapTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Row(
            children: [
              // Live indicator
              _GlassPill(
                dotColor: AppColors.mint500,
                child: Text(
                  '${_members.values.where((m) => m['online'] == true).length} متصل',
                  style: AppTypography.labelMd.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Group code pill
              Expanded(
                child: _GlassPill(
                  icon: Icons.tag_rounded,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'المجموعة: ',
                        style: AppTypography.labelMd.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        widget.groupCode,
                        style: AppTypography.labelLg.copyWith(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembersCard() {
    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: widget.embedded
          ? AppSpacing.lg
          : AppSpacing.xxxl * 2.5,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'الأعضاء القريبون',
                        style: AppTypography.titleSm.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      const StatusPill(
                        label: 'مباشر',
                        color: AppColors.mint500,
                        dot: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _members.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (_, i) {
                        final entry = _members.entries.elementAt(i);
                        final isMe = entry.key == _fb.userId;
                        final isFollowed = entry.key == _followingMemberId;
                        return _MemberChip(
                          name: (entry.value['name'] as String?) ?? '',
                          isMe: isMe,
                          isFollowed: isFollowed,
                          onTap: () {
                            if (isMe) {
                              _showAll();
                            } else {
                              _selectMember(entry.key);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.ink900.withValues(alpha: 0.6),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'جارٍ تحضير الخريطة...',
                style: AppTypography.titleMd.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'يتم تحميل موقعك',
                style: AppTypography.bodySm.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Old _buildAppBar removed in v1.9.0 redesign — top bar is now
  // [build] -> [_buildMapTopBar] (glass pill overlay) instead.

  Widget _buildBottomNav() {
    return AppBottomNav(
      selectedIndex: 0,
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

// ═══════════════════════════════════════════════════════════════
//  PRIVATE HELPER WIDGETS — used by the redesigned map screen
// ═══════════════════════════════════════════════════════════════

class _AlertComposerGrid extends StatelessWidget {
  final void Function(AlertType type) onSelect;
  const _AlertComposerGrid({required this.onSelect});

  IconData _iconFor(AlertType t) => switch (t) {
    AlertType.police => Icons.local_police_rounded,
    AlertType.speedTrap => Icons.speed_rounded,
    AlertType.control => Icons.supervisor_account_rounded,
    AlertType.hazard => Icons.warning_rounded,
    AlertType.accident => Icons.car_crash_rounded,
    AlertType.badCustomer => Icons.person_off_rounded,
    AlertType.note => Icons.sticky_note_2_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final alertTypes = AlertType.values.where((t) => t.isAlert).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 2.4,
      ),
      itemCount: alertTypes.length,
      itemBuilder: (ctx, i) {
        final type = alertTypes[i];
        return Material(
          color: type.color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: () => onSelect(type),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: type.color.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _iconFor(type),
                      color: type.color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      type.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassPill extends StatelessWidget {
  final Widget child;
  final IconData? icon;
  final Color? dotColor;
  const _GlassPill({required this.child, this.icon, this.dotColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor!.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ] else if (icon != null) ...[
                Icon(icon, color: Colors.white70, size: 14),
                const SizedBox(width: AppSpacing.xs),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

enum _FabVariant { primary, secondary }

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? extended;
  final _FabVariant variant;
  const _MapFab({
    required this.icon,
    required this.onPressed,
    this.extended,
    this.variant = _FabVariant.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = variant == _FabVariant.primary;
    final bg = isPrimary ? AppColors.indigo500 : Colors.white;
    final fg = isPrimary ? Colors.white : AppColors.indigo600;
    final size = AppSpacing.fab;
    final radius = BorderRadius.circular(AppRadius.lg);
    final shape = RoundedRectangleBorder(borderRadius: radius);
    if (extended != null) {
      return Material(
        color: bg,
        shape: shape,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  extended!,
                  style: AppTypography.buttonMd.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      color: bg,
      shape: shape,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: fg, size: 24),
        ),
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  final String name;
  final bool isMe;
  final bool isFollowed;
  final VoidCallback onTap;
  const _MemberChip({
    required this.name,
    required this.isMe,
    required this.isFollowed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMe
        ? AppColors.orange500
        : isFollowed
            ? AppColors.indigo500
            : AppColors.indigo300;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isFollowed
                ? AppColors.indigo500.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isFollowed
                  ? AppColors.indigo500.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name.characters.first : '?',
                    style: AppTypography.labelSm.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isMe ? 'أنت' : name,
                style: AppTypography.labelMd.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetSectionLabel extends StatelessWidget {
  final String text;
  const _SheetSectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.ink500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
