import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';
import '../services/alert_service.dart';

class AdminPanelScreen extends StatefulWidget {
  final String groupCode;

  const AdminPanelScreen({super.key, required this.groupCode});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final FirebaseService _fb = FirebaseService();
  final AlertService _alertSvc = AlertService();

  StreamSubscription<DatabaseEvent>? _membersSub;
  StreamSubscription<List<AlertData>>? _alertsSub;

  Map<String, Map<String, dynamic>> _members = {};
  List<AlertData> _alerts = [];

  @override
  void initState() {
    super.initState();
    _listenMembers();
    _listenAlerts();
  }

  void _listenMembers() {
    _membersSub = _fb.watchGroupMembers(widget.groupCode).listen((event) {
      if (!mounted) return;
      final snap = event.snapshot;
      if (!snap.exists || snap.value is! Map) return;
      final data = snap.value as Map<dynamic, dynamic>;
      final updated = <String, Map<String, dynamic>>{};
      data.forEach((key, value) {
        if (key == '_meta' || key == '_chat' || key == '_alerts') return;
        if (value is! Map) return;
        updated[key.toString()] = {
          'name': (value['name'] as String?) ?? 'بدون اسم',
          'online': value['online'] as bool? ?? false,
          'icon': (value['icon'] as String?) ?? '',
          'lat': (value['lat'] as num?)?.toDouble() ?? 0.0,
          'lng': (value['lng'] as num?)?.toDouble() ?? 0.0,
        };
      });
      if (mounted) setState(() => _members = updated);
    });
  }

  void _listenAlerts() {
    _alertsSub = _alertSvc.watchAlerts(widget.groupCode).listen((alerts) {
      if (!mounted) return;
      setState(() => _alerts = alerts);
    });
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _alertsSub?.cancel();
    super.dispose();
  }

  Future<void> _removeMember(String userId, String name) async {
    final confirmed = await _confirmDialog(
      'إزالة عضو',
      'هل أنت متأكد من إزالة "$name" من المجموعة؟',
    );
    if (!confirmed || !mounted) return;
    await _fb.removeMemberFromGroup(
      groupCode: widget.groupCode,
      targetUserId: userId,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إزالة "$name" من المجموعة'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteAlert(AlertData alert) async {
    final confirmed = await _confirmDialog(
      'حذف بلاغ',
      'هل أنت متأكد من حذف "${alert.type.label}"؟',
    );
    if (!confirmed || !mounted) return;
    await _alertSvc.deleteAlert(widget.groupCode, alert.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حذف "${alert.type.label}"'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<bool> _confirmDialog(String title, String content) async {
    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: theme.textTheme.titleLarge),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, size: 22, color: Colors.amber),
            const SizedBox(width: 8),
            const Text('لوحة المشرف'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Members Section ──
          Text('الأعضاء (${_members.length})',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا يوجد أعضاء')))
          else
            ..._members.entries.map((e) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text((e.value['icon'] as String).isNotEmpty
                      ? e.value['icon'] as String : '🧑', style: const TextStyle(fontSize: 18)),
                ),
                title: Text(e.value['name'] as String),
                subtitle: Text(e.key == _fb.userId ? 'أنت' : ''),
                trailing: e.key == _fb.userId
                    ? null
                    : IconButton(
                        icon: Icon(Icons.person_remove_rounded, color: Colors.red),
                        onPressed: () => _removeMember(e.key, e.value['name'] as String),
                      ),
              ),
            )),
          const SizedBox(height: 24),
          // ── Alerts Section ──
          Text('التنبيهات (${_alerts.length})',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_alerts.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد تنبيهات')))
          else
            ..._alerts.map((alert) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: alert.type.color.withValues(alpha: 0.15),
                  child: Icon(_alertIcon(alert.type), color: alert.type.color, size: 20),
                ),
                title: Text(alert.type.label),
                subtitle: Text(
                  '${alert.reason.isNotEmpty ? "${alert.reason} • " : ""}'
                  '${alert.userName}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_rounded, color: Colors.red),
                  onPressed: () => _deleteAlert(alert),
                ),
              ),
            )),
        ],
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
}
