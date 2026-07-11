import 'package:flutter/foundation.dart';

/// Sanitize a string for use as a Firebase Realtime Database path segment.
///
/// Firebase path keys MUST NOT contain: `.`, `$`, `#`, `[`, `]`, `/`
/// Replaces illegal characters with `_`. Trims whitespace.
/// Throws if the result is empty.
String sanitizeFirebaseKey(String value) {
  final trimmed = value.trim();
  final sanitized = trimmed.replaceAll(RegExp(r'[.#\$\[\]/]'), '_');
  if (sanitized.isEmpty) {
    throw ArgumentError('Firebase key cannot be empty after sanitization');
  }
  if (sanitized != value) {
    debugPrint('[FirebasePath] Sanitized: "$value" -> "$sanitized"');
  }
  return sanitized;
}

/// Build a child path with sanitization and logging.
///
/// Example: `live/${sanitizeFirebaseKey(groupCode)}/${sanitizeFirebaseKey(userId)}`
String firebaseChild(String parent, String childKey) {
  final sanitized = sanitizeFirebaseKey(childKey);
  final path = '$parent/$sanitized';
  debugPrint('[FirebasePath] Path: "$parent/$childKey" -> "$path"');
  return path;
}
