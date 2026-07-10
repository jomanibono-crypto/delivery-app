import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the proximity notification threshold using shared_preferences.
///
/// The user can set any custom distance in meters (e.g. 50, 200, 1000).
/// The value survives app restarts. The default is 300m if nothing is saved.
class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  static const String _thresholdKey = 'proximity_threshold_meters';
  static const int defaultThreshold = 300;

  int _proximityThreshold = defaultThreshold;
  int get proximityThreshold => _proximityThreshold;

  /// Whether the threshold has been loaded from disk at least once.
  bool _loaded = false;

  /// Load the saved threshold from shared_preferences.
  /// Call this once at app startup. Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _proximityThreshold = prefs.getInt(_thresholdKey) ?? defaultThreshold;
      _loaded = true;
      debugPrint('[AppSettings] Loaded threshold=${_proximityThreshold}m');
    } catch (e) {
      debugPrint('[AppSettings] Failed to load threshold: $e');
      _proximityThreshold = defaultThreshold;
    }
    notifyListeners();
  }

  /// Update the proximity notification threshold and persist it to disk.
  Future<void> setProximityThreshold(int value) async {
    if (value <= 0) {
      debugPrint('[AppSettings] Rejected non-positive threshold: $value');
      return;
    }
    _proximityThreshold = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_thresholdKey, value);
      debugPrint('[AppSettings] Saved threshold=${value}m');
    } catch (e) {
      debugPrint('[AppSettings] Failed to save threshold: $e');
    }
  }

  /// Reset to default (mainly for testing).
  Future<void> reset() async {
    await setProximityThreshold(defaultThreshold);
  }
}
