import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_service.dart';
import '../utils/firebase_path.dart';

enum AlertType {
  police('🚔 شرطة', 'police', 0xFF1565C0),
  speedTrap('📸 رادار', 'speedtrap', 0xFFE65100),
  control('🧑‍💼 مراقب', 'control', 0xFF2E7D32),
  hazard('⚠️ خطر', 'hazard', 0xFFFF6F00),
  accident('💥 حادث', 'accident', 0xFFD32F2F),
  note('📝 ملاحظة', 'note', 0xFF6A1B9A),
  badCustomer('🚫 عميل سيء', 'bad_customer', 0xFFD32F2F);

  final String label;
  final String key;
  final int colorValue;

  const AlertType(this.label, this.key, this.colorValue);

  Color get color => Color(colorValue);

  static AlertType fromKey(String key) {
    return AlertType.values.firstWhere((t) => t.key == key);
  }

  bool get isAlert => this != AlertType.note;
}

class AlertData {
  final String id;
  final AlertType type;
  final double lat;
  final double lng;
  final String userId;
  final String userName;
  final String groupCode;
  final int timestamp;
  final bool resolved;
  final String note;
  final String reason;
  final Map<String, String> votes;

  AlertData({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.userId,
    required this.userName,
    required this.groupCode,
    required this.timestamp,
    this.resolved = false,
    this.note = '',
    this.reason = '',
    this.votes = const {},
  });

  int get voteCountStillThere =>
      votes.values.where((v) => v == 'still_there').length;
  int get voteCountGone => votes.values.where((v) => v == 'gone').length;
  bool get votedGoneByCurrentUser => votes.values.any((v) => v == 'gone');

  factory AlertData.fromMap(
    Map<dynamic, dynamic> map,
    String id,
    String groupCode,
  ) {
    final votesRaw = map['votes'] is Map
        ? map['votes'] as Map<dynamic, dynamic>
        : null;
    final votes = <String, String>{};
    if (votesRaw != null) {
      for (final entry in votesRaw.entries) {
        if (entry.value is String) {
          votes[entry.key.toString()] = entry.value as String;
        }
      }
    }
    return AlertData(
      id: id,
      type: AlertType.fromKey(map['type'] as String? ?? 'police'),
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      userId: map['userId'] as String? ?? '',
      userName: map['userName'] as String? ?? '',
      groupCode: groupCode,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      resolved: map['resolved'] as bool? ?? false,
      note: map['note'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      votes: votes,
    );
  }
}

class AlertService {
  final FirebaseService _firebase = FirebaseService();
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<String> addAlert({
    required String groupCode,
    required AlertType type,
    required double lat,
    required double lng,
    String note = '',
    String reason = '',
  }) async {
    await _firebase.signInAnonymously();
    final uid = _firebase.userId;
    final userName = _firebase.currentUser?.displayName ?? 'عضو';
    final ref = _db.child('live/${sanitizeFirebaseKey(groupCode)}/_alerts').push();
    final data = <String, dynamic>{
      'type': type.key,
      'lat': lat,
      'lng': lng,
      'userId': uid,
      'userName': userName,
      'timestamp': ServerValue.timestamp,
      'resolved': false,
    };
    if (note.isNotEmpty) data['note'] = note;
    if (reason.isNotEmpty) data['reason'] = reason;
    await ref.set(data);
    return ref.key ?? '';
  }

  Future<void> deleteAlert(String groupCode, String alertId) async {
    await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_alerts/${sanitizeFirebaseKey(alertId)}').remove();
  }

  Stream<List<AlertData>> watchAlerts(String groupCode) {
    return _db.child('live/${sanitizeFirebaseKey(groupCode)}/_alerts').onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists) return [];
      final data = snap.value as Map<dynamic, dynamic>? ?? {};
      final alerts = <AlertData>[];
      data.forEach((key, val) {
        if (val is Map) {
          alerts.add(AlertData.fromMap(val, key as String, groupCode));
        }
      });
      alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return alerts;
    });
  }

  /// Submit a vote for an alert.
  /// [vote] is 'still_there' or 'gone'.
  Future<void> submitVote({
    required String groupCode,
    required String alertId,
    required String vote,
  }) async {
    await _firebase.signInAnonymously();
    final uid = _firebase.userId;
    await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_alerts/${sanitizeFirebaseKey(alertId)}/votes/${sanitizeFirebaseKey(uid)}').set(vote);
  }

  /// Auto-remove alerts where enough users voted "gone".
  /// Threshold: at least 2 "gone" votes (configurable).
  /// Called after each alert update.
  Future<void> removeVotedGoneAlerts(
    String groupCode, {
    int threshold = 2,
  }) async {
    final snap = await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_alerts').get();
    if (!snap.exists) return;
    final data = snap.value is Map ? snap.value as Map<dynamic, dynamic> : null;
    if (data == null) return;
    for (final entry in data.entries) {
      if (entry.value is Map) {
        final map = entry.value as Map<dynamic, dynamic>;
        final votes = map['votes'] is Map
            ? map['votes'] as Map<dynamic, dynamic>
            : null;
        if (votes == null) continue;
        int goneCount = 0;
        for (final v in votes.values) {
          if (v == 'gone') goneCount++;
        }
        if (goneCount >= threshold) {
          await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_alerts/${sanitizeFirebaseKey(entry.key as String)}').remove();
          debugPrint(
            '[Alert] Auto-removed ${entry.key} — $goneCount "gone" votes',
          );
        }
      }
    }
  }

  /// Delete alerts older than [expirationHours] (default 12 for police/radar/etc).
  Future<int> cleanupExpiredAlerts(
    String groupCode, {
    int expirationHours = 12,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoff = nowMs - (expirationHours * 3600000);
    final snap = await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_alerts').get();
    if (!snap.exists) return 0;
    final data = snap.value as Map<dynamic, dynamic>? ?? {};
    int deleted = 0;
    for (final entry in data.entries) {
      if (entry.value is Map) {
        final map = entry.value as Map<dynamic, dynamic>;
        final ts = (map['timestamp'] as num?)?.toInt() ?? 0;
        final type = AlertType.fromKey(map['type'] as String? ?? 'police');
        if (ts > 0 && ts < cutoff && type.isAlert) {
          try {
            await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_alerts/${sanitizeFirebaseKey(entry.key as String)}').remove();
            deleted++;
          } catch (_) {}
        }
      }
    }
    return deleted;
  }

  /// Delete chat messages older than [expirationHours] (default 1).
  Future<int> cleanupExpiredMessages(
    String groupCode, {
    int expirationHours = 1,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoff = nowMs - (expirationHours * 3600000);
    final snap = await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_chat').get();
    if (!snap.exists) return 0;
    final data = snap.value as Map<dynamic, dynamic>? ?? {};
    int deleted = 0;
    for (final entry in data.entries) {
      if (entry.value is Map) {
        final map = entry.value as Map<dynamic, dynamic>;
        final ts = (map['timestamp'] as num?)?.toInt() ?? 0;
        if (ts > 0 && ts < cutoff) {
          try {
            await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_chat/${sanitizeFirebaseKey(entry.key as String)}').remove();
            deleted++;
          } catch (_) {}
        }
      }
    }
    return deleted;
  }
}
