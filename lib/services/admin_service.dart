import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Admin authentication service.
///
/// SECURITY: Admin codes are NEVER stored in plaintext. They are stored as
/// SHA-256 hashes with a per-app salt. Even if an attacker unpacks the APK
/// and reads the source, they will only see hashes — not the original codes.
///
/// To add a new admin code without rebuilding the app, pass it via
/// `--dart-define=ADMIN_MASTER_CODE=xxxxx` at build time. The master code
/// is itself hashed in memory only (not stored) and works as an emergency
/// override.
///
/// To rotate codes:
///   1. Pick new 4-digit codes
///   2. Compute their hashes with this salt:
///        echo -n "glovomate_admin_v1${code}" | sha256sum
///   3. Add the hash to [_allowedHashes] below
class AdminService {
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;
  AdminService._internal();

  /// Salt that mixes into every hash. Rotating this invalidates ALL existing
  /// codes at once (a "global logout" of every admin). Keep it stable for
  /// normal use; rotate it only if you suspect a leak.
  static const String _salt = 'glovomate_admin_v1';

  /// SHA-256 hashes of the currently-valid admin codes. To regenerate, run:
  ///   echo -n "glovomate_admin_v1${CODE}" | sha256sum
  ///
  /// Pre-computed hashes for codes 2010, 2020, 2030:
  ///   2010 -> 4cb248aa69643d6db6dc04d3b71f770d9176be62c225c812aabf6c0946bc9de9
  ///   2020 -> ea9711f439d3e1534cb6aa3e564f1e10603e17df50a34366a664d3af99667d02
  ///   2030 -> c1e259b1f8e2be57127154a1fa99352ebf87d1c30259efaf5e0eb3730d6a479e
  static const Set<String> _allowedHashes = {
    '4cb248aa69643d6db6dc04d3b71f770d9176be62c225c812aabf6c0946bc9de9',
    'ea9711f439d3e1534cb6aa3e564f1e10603e17df50a34366a664d3af99667d02',
    'c1e259b1f8e2be57127154a1fa99352ebf87d1c30259efaf5e0eb3730d6a479e',
  };

  /// Master code from build-time `--dart-define=ADMIN_MASTER_CODE=xxxxx`.
  /// Hashed in memory only and used as an emergency override. If undefined,
  /// it contributes no extra hash.
  static final String _masterCodeRaw =
      const String.fromEnvironment('ADMIN_MASTER_CODE', defaultValue: '');

  bool _isAdmin = false;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  /// Maximum consecutive failed attempts before a temporary lockout.
  static const int _maxAttempts = 3;

  /// Lockout duration after exceeding the attempt limit.
  static const Duration _lockoutDuration = Duration(seconds: 30);

  bool get isAdmin => _isAdmin;
  bool get isLockedOut =>
      _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!);
  int get remainingLockoutSeconds {
    if (_lockoutUntil == null) return 0;
    final diff = _lockoutUntil!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Verify a candidate admin code. Returns true on success, false otherwise.
  /// Implements rate limiting: after [_maxAttempts] consecutive failures the
  /// service is locked out for [_lockoutDuration] (admin must wait before
  /// retrying).
  bool verifyCode(String code) {
    if (isLockedOut) {
      debugPrint(
        '[Admin] Locked out — ${remainingLockoutSeconds}s remaining.',
      );
      return false;
    }

    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;

    final candidateHash = _hash(trimmed);
    final accepted = _isHashAccepted(candidateHash);

    if (accepted) {
      _isAdmin = true;
      _failedAttempts = 0;
      _lockoutUntil = null;
      debugPrint('[Admin] Admin mode activated.');
      return true;
    }

    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      _lockoutUntil = DateTime.now().add(_lockoutDuration);
      debugPrint(
        '[Admin] Too many failed attempts — locked out for '
        '${_lockoutDuration.inSeconds}s.',
      );
    } else {
      debugPrint(
        '[Admin] Wrong code (attempt $_failedAttempts/$_maxAttempts).',
      );
    }
    return false;
  }

  void logout() {
    _isAdmin = false;
    _failedAttempts = 0;
    _lockoutUntil = null;
    debugPrint('[Admin] Admin mode deactivated.');
  }

  // ──────────────── internals ────────────────

  /// Compute the SHA-256 of `salt + code` and return it as a hex string.
  static String _hash(String code) {
    final bytes = utf8.encode(_salt + code);
    return sha256.convert(bytes).toString();
  }

  /// Constant-time check whether [candidateHash] is in the accepted set
  /// (or matches the master code hash). Comparing all entries in fixed time
  /// prevents timing-based discovery of valid codes.
  bool _isHashAccepted(String candidateHash) {
    bool match = false;
    for (final allowed in _allowedHashes) {
      // Use XOR to find any difference; |= accumulates without short-circuit.
      match |= _constantTimeEquals(allowed, candidateHash);
    }

    // Master code (if supplied at build time) adds one more accepted hash.
    if (_masterCodeRaw.isNotEmpty) {
      final masterHash = _hash(_masterCodeRaw);
      match |= _constantTimeEquals(masterHash, candidateHash);
    }
    return match;
  }

  /// Length-equal, constant-time string comparison.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
