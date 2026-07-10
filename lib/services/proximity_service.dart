import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'alert_service.dart';
import 'voice_service.dart';

/// Monitors user distance to alert markers and triggers a configurable
/// proximity notification when the user enters the configured radius.
///
/// Each marker notifies only once. State resets when the user moves
/// 500m+ away from that marker.
class ProximityService {
  final FlutterLocalNotificationsPlugin _notifPlugin;

  ProximityService(this._notifPlugin);

  // Marker ID → has this marker already been notified?
  final Map<String, bool> _notifiedAlerts = {};

  /// Called with the user's current position and all active alerts.
  /// Returns the number of notifications sent this call.
  ///
  /// All configuration parameters are optional — defaults match the
  /// previous hardcoded behavior for backward compatibility.
  int checkProximity({
    required double myLat,
    required double myLng,
    required List<AlertData> alerts,
    required String groupCode,
    int alertDistance = 200,
    List<String> enabledTypes = const [
      'police',
      'speedtrap',
      'control',
      'bad_customer',
      'hazard',
      'accident',
    ],
    bool enableNotification = true,
    bool enableVibration = true,
    bool enableSound = true,
    bool enableVoice = false,
  }) {
    if (myLat == 0.0 && myLng == 0.0) return 0;
    int triggered = 0;

    for (final alert in alerts) {
      if (!alert.type.isAlert) continue;
      if (alert.resolved) continue;
      if (!enabledTypes.contains(alert.type.key)) continue;

      final distance = _haversine(myLat, myLng, alert.lat, alert.lng);
      final wasNotified = _notifiedAlerts[alert.id] ?? false;

      // Reset: user moved 500m+ away from closest approach
      if (wasNotified && distance > 500) {
        _notifiedAlerts[alert.id] = false;
        debugPrint(
          '[Proximity] Reset marker ${alert.id} — user left area (${distance.toStringAsFixed(0)}m)',
        );
      }

      if (distance <= alertDistance && !wasNotified) {
        _notifiedAlerts[alert.id] = true;
        _showAlertNotif(
          alert,
          distance,
          enableNotification: enableNotification,
          enableVibration: enableVibration,
          enableSound: enableSound,
        );
        triggered++;
        debugPrint(
          '[Proximity] ALERT: ${alert.type.label} at ${distance.toStringAsFixed(0)}m (limit=${alertDistance}m)',
        );

        // Voice alert
        if (enableVoice) {
          VoiceService().speakAlert(alert.type.label);
        }
      }
    }
    return triggered;
  }

  void _showAlertNotif(
    AlertData alert,
    double distance, {
    required bool enableNotification,
    required bool enableVibration,
    required bool enableSound,
  }) {
    if (!enableNotification) return;

    final distFormatted = distance < 1000
        ? '${distance.toStringAsFixed(0)}م'
        : '${(distance / 1000).toStringAsFixed(1)}كم';

    final vibePattern = enableVibration
        ? Int64List.fromList([0, 500, 200, 500, 200, 500, 200, 500])
        : null;

    _notifPlugin.show(
      5000 + alert.id.hashCode,
      '🔴 ${alert.type.label} قريب!',
      '${alert.type.label} على بعد $distFormatted\n${alert.note.isNotEmpty ? 'ملاحظة: ${alert.note}' : ''}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'proximity_channel_v3',
          'Proximity Alerts',
          channelDescription: 'Notifications when alert markers are nearby',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          playSound: enableSound,
          enableVibration: enableVibration,
          vibrationPattern: vibePattern,
          fullScreenIntent: false,
          visibility: NotificationVisibility.public,
          autoCancel: true,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );

    // Vibrate ~1-2 seconds if notification is shown and vibration is enabled
    if (enableVibration) {
      HapticFeedback.heavyImpact();
    }
  }

  /// Haversine distance in meters between two lat/lng points.
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * pi / 180;
}
