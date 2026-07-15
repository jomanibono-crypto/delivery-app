import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../utils/firebase_path.dart';

/// Centralized Firebase service handling anonymous auth and realtime database.
class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // ──────────────────── SHARED WRITE (callable from any isolate) ────────────────────

  /// Shared static location-write function.
  ///
  /// Both the UI isolate (home_screen.dart) and the background-service isolate
  /// (main.dart onStart) call THIS to write a position, ensuring identical data
  /// shape and path. Does NOT rely on instance state, so it's safe from any
  /// isolate after Firebase is initialized there.
  static Future<void> writeLocationToFirebase({
    required String groupCode,
    required String userId,
    required String name,
    required double lat,
    required double lng,
    double speed = 0.0,
    String? icon,
    bool online = true,
  }) async {
    try {
      final db = FirebaseDatabase.instance.ref();
      final sk = sanitizeFirebaseKey;
      final ref = db.child('live/${sk(groupCode)}/${sk(userId)}');
      final data = <String, dynamic>{
        'name': name,
        'lat': lat,
        'lng': lng,
        'timestamp': ServerValue.timestamp,
        'online': online,
        'speed': speed,
      };
      if (icon != null && icon.isNotEmpty) data['icon'] = icon;
      if (speed > 0) data['last_moved_at'] = ServerValue.timestamp;
      await ref.set(data);
      await ref.onDisconnect().remove();
    } catch (e, s) {
      debugPrint('[FirebaseDB] writeLocationToFirebase failed: $e');
      FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
    }
  }

  User? get currentUser => _auth.currentUser;
  String get userId => _auth.currentUser?.uid ?? '';

  /// Anonymous sign-in — no email/password required.
  Future<void> signInAnonymously() async {
    if (_auth.currentUser != null) {
      debugPrint(
        '[FirebaseAuth] Already signed in: uid=${_auth.currentUser!.uid}',
      );
      return;
    }
    debugPrint('[FirebaseAuth] Signing in anonymously...');
    final cred = await _auth.signInAnonymously();
    debugPrint('[FirebaseAuth] Anonymous sign-in OK: uid=${cred.user?.uid}');
  }

  /// Ensure an authenticated user exists before any database write.
  /// Throws a descriptive error if sign-in failed or the UID is null.
  Future<void> _ensureAuthenticated() async {
    if (_auth.currentUser == null) {
      debugPrint(
        '[FirebaseAuth] No current user — attempting anonymous sign-in.',
      );
      await signInAnonymously();
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception(
        'Authentication failed: anonymous user UID is null after sign-in. '
        'Cannot write to Realtime Database.',
      );
    }
    debugPrint('[FirebaseAuth] Authenticated and ready to write. uid=$uid');
  }

  // ──────────────────── Group Operations ────────────────────

  /// Generate a random 6-digit group code and write metadata to
  /// live/{code}/_meta so it's covered by the "live/{group_code}" security rules.
  /// Returns the generated code.
  Future<String> createGroup() async {
    // Enforce authentication BEFORE attempting to write to the database.
    await _ensureAuthenticated();

    // AUDIT-D: avoid group-code collisions. The old generator was purely
    // time-based (ms % 1e6), so two devices creating a group within the
    // same millisecond would collide. We now retry with a random suffix
    // until we find a code whose _meta node doesn't already exist.
    String code;
    for (var attempt = 0; attempt < 5; attempt++) {
      code = _generateGroupCode();
      final metaRef = _db.child('live/${sanitizeFirebaseKey(code)}/_meta');
      final existing = await metaRef.get();
      if (!existing.exists) {
        debugPrint(
          '[FirebaseDB] Writing group meta: live/$code/_meta (uid=$userId)',
        );
        await metaRef.set({
          'created': ServerValue.timestamp,
          'createdBy': userId,
        });
        debugPrint('[FirebaseDB] Group created successfully: $code');
        return code;
      }
      debugPrint(
        '[FirebaseDB] Code $code already in use, retrying (attempt ${attempt + 1})...',
      );
    }
    // Extremely unlikely fallback — surface a clear error.
    throw Exception('تعذّر إنشاء كود فريد بعد عدة محاولات. حاول مرة أخرى.');
  }

  /// Check whether a group code exists in the database.
  /// Reads live/{code}/_meta which is covered by "live/{group_code}" rules.
  Future<bool> groupExists(String code) async {
    await _ensureAuthenticated();
    final snap = await _db.child('live/${sanitizeFirebaseKey(code)}/_meta').get();
    return snap.exists;
  }

  // ──────────────────── Live Location Operations ────────────────────

  /// Register a user's node under live/{groupCode}/{userId} with location data.
  /// Uses SET (overwrite), never PUSH.
  /// Also sets up onDisconnect().remove() for automatic cleanup.
  Future<void> updateUserLocation({
    required String groupCode,
    required String name,
    required double lat,
    required double lng,
    String? icon,
    double speed = 0.0,
    bool online = true,
  }) async {
    try {
      await _ensureAuthenticated();
      final ref = _db.child('live/${sanitizeFirebaseKey(groupCode)}/${sanitizeFirebaseKey(userId)}');
      final data = <String, dynamic>{
        'name': name,
        'lat': lat,
        'lng': lng,
        'timestamp': ServerValue.timestamp,
        'online': online,
        'speed': speed,
      };
      if (icon != null && icon.isNotEmpty) data['icon'] = icon;
      if (speed > 0) data['last_moved_at'] = ServerValue.timestamp;
      await ref.update(data);
      await ref.onDisconnect().remove();
    } catch (e, s) {
      // AUDIT-A: a failed upload (network glitch, permission) should NOT crash
      // the location stream. Log and move on — the next update will retry.
      debugPrint(
        '[FirebaseDB] updateUserLocation failed (will retry next tick): $e',
      );
      FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
    }
  }

  /// Update ONLY the user's display name (no location change).
  Future<void> updateUserName({
    required String groupCode,
    required String newName,
  }) async {
    try {
      await _ensureAuthenticated();
      await _db.child('live/${sanitizeFirebaseKey(groupCode)}/${sanitizeFirebaseKey(userId)}/name').set(newName);
    } catch (e) {
      debugPrint('[FirebaseDB] updateUserName failed: $e');
    }
  }

  /// Update ONLY the user's avatar icon (no location change).
  /// Used when the user picks a new emoji in settings.
  Future<void> updateUserIcon({
    required String groupCode,
    required String icon,
  }) async {
    try {
      await _ensureAuthenticated();
      await _db.child('live/${sanitizeFirebaseKey(groupCode)}/${sanitizeFirebaseKey(userId)}/icon').set(icon);
    } catch (e) {
      debugPrint('[FirebaseDB] updateUserIcon failed: $e');
    }
  }

  /// Listen to all members in a group in real-time.
  Stream<DatabaseEvent> watchGroupMembers(String groupCode) {
    return _db.child('live/${sanitizeFirebaseKey(groupCode)}').onValue;
  }

  /// Remove the current user's node — called on manual "Leave Group".
  Future<void> removeUserFromGroup(String groupCode) async {
    await _db.child('live/${sanitizeFirebaseKey(groupCode)}/${sanitizeFirebaseKey(userId)}').remove();
  }

  // ──────────────────── Chat Messages ────────────────────

  /// Create a minimal presence node when a user joins a group, so the
  /// security rules (which check root.child(...auth.uid).exists()) pass
  /// before the first GPS location is written.
  Future<void> createPresenceNode({
    required String groupCode,
    required String name,
    String? icon,
  }) async {
    try {
      await _ensureAuthenticated();
      final ref = _db.child('live/${sanitizeFirebaseKey(groupCode)}/${sanitizeFirebaseKey(userId)}');
      final data = <String, dynamic>{
        'name': name,
        'lat': 0.0,
        'lng': 0.0,
        'timestamp': ServerValue.timestamp,
        'online': true,
        'speed': 0,
      };
      if (icon != null && icon.isNotEmpty) data['icon'] = icon;
      await ref.set(data);
      await ref.onDisconnect().remove();
      debugPrint('[FirebaseDB] Presence node created: live/$groupCode/$userId');
    } catch (e, s) {
      debugPrint('[FirebaseDB] createPresenceNode failed: $e');
      FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
    }
  }

  /// Send a chat message to the group.
  Future<void> sendMessage({
    required String groupCode,
    required String message,
    String? icon,
  }) async {
    try {
      await _ensureAuthenticated();
      final ref = _db.child('live/${sanitizeFirebaseKey(groupCode)}/_chat').push();
      await ref.set({
        'userId': userId,
        'name': _auth.currentUser?.displayName ?? 'عضو',
        'message': message,
        'timestamp': ServerValue.timestamp,
        if (icon != null && icon.isNotEmpty) 'icon': icon,
      });
    } catch (e) {
      debugPrint('[FirebaseDB] sendMessage failed: $e');
    }
  }

  /// Listen to new chat messages in real-time (newest last).
  Stream<DatabaseEvent> watchMessages(String groupCode) {
    return _db.child('live/${sanitizeFirebaseKey(groupCode)}/_chat').orderByChild('timestamp').onValue;
  }

  /// Get current user's stored name from Firebase.
  Future<String?> getUserName(String groupCode) async {
    final snap = await _db.child('live/${sanitizeFirebaseKey(groupCode)}/${sanitizeFirebaseKey(userId)}/name').get();
    return snap.value as String?;
  }

  /// Push a history point (lat/lng) for route tracking.
  /// Called periodically from background service.
  static Future<void> writeHistoryPoint({
    required String groupCode,
    required String userId,
    required double lat,
    required double lng,
    double speed = 0.0,
  }) async {
    try {
      final db = FirebaseDatabase.instance.ref();
      final sk = sanitizeFirebaseKey;
      final ref = db.child('live/${sk(groupCode)}/${sk(userId)}/history').push();
      await ref.set({
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e, s) {
      debugPrint('[FirebaseDB] writeHistoryPoint failed: $e');
      FirebaseCrashlytics.instance.recordError(e, s, fatal: false);
    }
  }

  /// Fetch the most recent history points for route drawing.
  /// Returns up to [limit] points, ordered by timestamp ascending.
  static Future<List<Map<String, dynamic>>> getHistory({
    required String groupCode,
    required String userId,
    int limit = 200,
  }) async {
    try {
      final db = FirebaseDatabase.instance.ref();
      final sk = sanitizeFirebaseKey;
      final snap = await db
          .child('live/${sk(groupCode)}/${sk(userId)}/history')
          .orderByChild('timestamp')
          .limitToLast(limit)
          .get();
      if (!snap.exists) return [];
      final data = snap.value is Map
          ? snap.value as Map<dynamic, dynamic>
          : null;
      if (data == null) return [];
      final points = <Map<String, dynamic>>[];
      data.forEach((key, value) {
        if (value is Map) {
          points.add({
            'lat': (value['lat'] as num?)?.toDouble() ?? 0.0,
            'lng': (value['lng'] as num?)?.toDouble() ?? 0.0,
            'timestamp': (value['timestamp'] as num?)?.toInt() ?? 0,
          });
        }
      });
      points.sort(
        (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int),
      );
      return points;
    } catch (e) {
      debugPrint('[FirebaseDB] getHistory failed: $e');
      return [];
    }
  }

  // ──────────────────── Helpers ────────────────────

  String _generateGroupCode() {
    // AUDIT-D: combine a time component with a random suffix so two devices
    // creating a group in the same millisecond can't collide.
    final rng = Random();
    final timePart = DateTime.now().millisecondsSinceEpoch % 1000000;
    final randPart = rng.nextInt(1000000);
    final combined = (timePart ^ randPart) % 1000000;
    return combined.toString().padLeft(6, '0');
  }

  /// Delete a chat message by its push key.
  Future<void> deleteMessage({
    required String groupCode,
    required String messageId,
  }) async {
    try {
      await _db.child('live/${sanitizeFirebaseKey(groupCode)}/_chat/${sanitizeFirebaseKey(messageId)}').remove();
    } catch (e) {
      debugPrint('[FirebaseDB] deleteMessage failed: $e');
    }
  }

  /// Admin: remove any member from the group.
  Future<void> removeMemberFromGroup({
    required String groupCode,
    required String targetUserId,
  }) async {
    try {
      await _db.child('live/${sanitizeFirebaseKey(groupCode)}/${sanitizeFirebaseKey(targetUserId)}').remove();
    } catch (e) {
      debugPrint('[FirebaseDB] removeMemberFromGroup failed: $e');
    }
  }

  /// Sign out from Firebase auth entirely.
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
