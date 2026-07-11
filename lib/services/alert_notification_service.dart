import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';
import 'alert_service.dart';
import 'notification_service.dart';

/// Global alert notification listener that lives for the app's lifetime.
///
/// Listens for NEW alerts on Firebase and shows a local notification
/// for each one exactly once, regardless of which screen the user is on.
class AlertNotificationService {
  static final AlertNotificationService _instance =
      AlertNotificationService._internal();
  factory AlertNotificationService() => _instance;
  AlertNotificationService._internal();

  final NotificationService _notifService = NotificationService();
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// IDs of alerts we've already notified the user about (per session).
  final Set<String> _notifiedAlertIds = {};

  StreamSubscription<DatabaseEvent>? _subscription;
  String? _currentGroupCode;

  /// Start listening for new alerts in [groupCode].
  /// Call this once when the user enters a group (e.g., from HomeScreen).
  void startListening(String groupCode) {
    if (_subscription != null && _currentGroupCode == groupCode) return;
    stopListening();
    _currentGroupCode = groupCode;
    _subscription = _db
        .child('live/$groupCode/_alerts')
        .orderByChild('timestamp')
        .limitToLast(50)
        .onValue
        .listen((event) {
      final snap = event.snapshot;
      if (!snap.exists) return;
      final data = snap.value as Map<dynamic, dynamic>? ?? {};
      final userId = FirebaseService().userId;
      for (final entry in data.entries) {
        if (entry.value is! Map) continue;
        final map = entry.value as Map<dynamic, dynamic>;
        final alertId = entry.key as String;
        // Skip if already notified this session
        if (_notifiedAlertIds.contains(alertId)) continue;
        // Skip alerts created by the current user
        final alertUserId = map['userId'] as String? ?? '';
        if (alertUserId == userId) continue;
        // Skip non-alert types (notes)
        final typeKey = map['type'] as String? ?? '';
        final alertType = AlertType.values.where((t) => t.key == typeKey).firstOrNull;
        if (alertType == null || !alertType.isAlert) continue;
        // Mark as notified and show notification
        _notifiedAlertIds.add(alertId);
        _notifService.showAlertNotification(
          AlertData.fromMap(map, alertId, groupCode),
        ).catchError((_) {});
      }
    });
    debugPrint('[AlertNotif] Started listening for group $groupCode');
  }

  /// Stop listening. Call on group leave.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _currentGroupCode = null;
  }

  /// Clear the notified-IDs cache (e.g., on group change).
  void clearCache() {
    _notifiedAlertIds.clear();
  }
}
