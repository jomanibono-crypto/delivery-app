import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_service.dart';
import '../utils/firebase_path.dart';

class BlacklistEntry {
  final String id;
  final String phone;
  final String normalized;
  final String reason;
  final String addedBy;
  final String addedByName;
  final int timestamp;
  /// Location of a persistent map marker. `null` for phone-only entries.
  final double? lat;
  /// Location of a persistent map marker. `null` for phone-only entries.
  final double? lng;
  /// Optional customer name shown on a map marker detail sheet.
  final String? name;

  BlacklistEntry({
    required this.id,
    required this.phone,
    required this.normalized,
    required this.reason,
    required this.addedBy,
    required this.addedByName,
    required this.timestamp,
    this.lat,
    this.lng,
    this.name,
  });

  /// True when this entry should render as a map marker.
  bool get hasMarker => lat != null && lng != null;

  factory BlacklistEntry.fromMap(Map<dynamic, dynamic> map, String id) {
    return BlacklistEntry(
      id: id,
      phone: map['phone'] as String? ?? '',
      normalized: map['normalized'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      addedBy: map['addedBy'] as String? ?? '',
      addedByName: map['addedByName'] as String? ?? 'عضو',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      name: map['name'] as String?,
    );
  }
}

class BlacklistService {
  final FirebaseService _firebase = FirebaseService();
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// Normalize a phone number for comparison:
  /// Strip spaces, dashes, plus; remove leading "00"/"0" if followed by "212"
  /// Returns digits-only string.
  static String normalize(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('00')) return digits.substring(2);
    if (digits.startsWith('212') && digits.length > 3) return digits;
    if (digits.startsWith('0')) return '212${digits.substring(1)}';
    return digits;
  }

  Future<void> addEntry({required String phone, required String reason}) async {
    await _firebase.signInAnonymously();
    final uid = _firebase.userId;
    final userName = _firebase.currentUser?.displayName ?? 'عضو';
    final ref = _db.child('blacklist').push();
    await ref.set({
      'phone': phone,
      'normalized': normalize(phone),
      'reason': reason,
      'addedBy': uid,
      'addedByName': userName,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> deleteEntry(String entryId) async {
    await _db.child('blacklist/${sanitizeFirebaseKey(entryId)}').remove();
  }

  Future<BlacklistEntry?> checkPhone(String phone) async {
    final normalized = normalize(phone);
    final snap = await _db.child('blacklist').get();
    if (!snap.exists) return null;
    final data = snap.value as Map<dynamic, dynamic>? ?? {};
    for (final entry in data.entries) {
      if (entry.value is Map) {
        final map = entry.value as Map<dynamic, dynamic>;
        if ((map['normalized'] as String?) == normalized) {
          return BlacklistEntry.fromMap(map, entry.key);
        }
      }
    }
    return null;
  }

  Stream<List<BlacklistEntry>> watchAll() {
    return _db.child('blacklist').onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists) return [];
      final data = snap.value as Map<dynamic, dynamic>? ?? {};
      final entries = <BlacklistEntry>[];
      data.forEach((key, val) {
        if (val is Map) {
          entries.add(BlacklistEntry.fromMap(val, key as String));
        }
      });
      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    });
  }
}
