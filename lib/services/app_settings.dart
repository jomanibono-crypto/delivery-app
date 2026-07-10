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

  // ──────────────────── Proximity Alert Distance ────────────────────

  static const List<int> alertDistanceOptions = [50, 100, 150, 200, 300, 500];
  static const String _alertDistanceKey = 'proximity_alert_distance';
  static const int defaultAlertDistance = 200;

  int _alertDistance = defaultAlertDistance;
  int get alertDistance => _alertDistance;

  Future<void> setAlertDistance(int value) async {
    if (!alertDistanceOptions.contains(value)) return;
    _alertDistance = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_alertDistanceKey, value);
      debugPrint('[AppSettings] Saved alertDistance=${value}m');
    } catch (e) {
      debugPrint('[AppSettings] Failed to save alert distance: $e');
    }
  }

  // ──────────────────── Enabled Alert Types ────────────────────

  static const String _enabledTypesKey = 'proximity_enabled_types';
  static const String defaultEnabledTypes =
      'police,speedtrap,control,bad_customer,hazard,accident';

  String _enabledAlertTypes = defaultEnabledTypes;
  String get enabledAlertTypes => _enabledAlertTypes;

  bool isAlertTypeEnabled(String key) =>
      _enabledAlertTypes.split(',').contains(key);

  Future<void> setAlertTypeEnabled(String key, bool enabled) async {
    final types = _enabledAlertTypes.split(',').toSet();
    if (enabled) {
      types.add(key);
    } else {
      types.remove(key);
    }
    _enabledAlertTypes = types.join(',');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_enabledTypesKey, _enabledAlertTypes);
      debugPrint('[AppSettings] Saved enabledAlertTypes=$_enabledAlertTypes');
    } catch (e) {
      debugPrint('[AppSettings] Failed to save enabled types: $e');
    }
  }

  // ──────────────────── Alert Notification Toggles ────────────────────

  static const String _notifEnabledKey = 'proximity_alert_notif';
  static const String _vibeEnabledKey = 'proximity_alert_vibe';
  static const String _soundEnabledKey = 'proximity_alert_sound';
  static const String _voiceEnabledKey = 'proximity_alert_voice';

  bool _alertNotificationEnabled = true;
  bool _alertVibrationEnabled = true;
  bool _alertSoundEnabled = true;
  bool _alertVoiceEnabled = false;

  bool get alertNotificationEnabled => _alertNotificationEnabled;
  bool get alertVibrationEnabled => _alertVibrationEnabled;
  bool get alertSoundEnabled => _alertSoundEnabled;
  bool get alertVoiceEnabled => _alertVoiceEnabled;

  Future<void> setAlertNotificationEnabled(bool value) async {
    _alertNotificationEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notifEnabledKey, value);
    } catch (e) {
      debugPrint('[AppSettings] Failed to save notif toggle: $e');
    }
  }

  Future<void> setAlertVibrationEnabled(bool value) async {
    _alertVibrationEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_vibeEnabledKey, value);
    } catch (e) {
      debugPrint('[AppSettings] Failed to save vibe toggle: $e');
    }
  }

  Future<void> setAlertSoundEnabled(bool value) async {
    _alertSoundEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundEnabledKey, value);
    } catch (e) {
      debugPrint('[AppSettings] Failed to save sound toggle: $e');
    }
  }

  Future<void> setAlertVoiceEnabled(bool value) async {
    _alertVoiceEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_voiceEnabledKey, value);
    } catch (e) {
      debugPrint('[AppSettings] Failed to save voice toggle: $e');
    }
  }

  // ──────────────────── Load Extended Settings ────────────────────

  Future<void> loadExtended() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _alertDistance = prefs.getInt(_alertDistanceKey) ?? defaultAlertDistance;
      _enabledAlertTypes =
          prefs.getString(_enabledTypesKey) ?? defaultEnabledTypes;
      _alertNotificationEnabled = prefs.getBool(_notifEnabledKey) ?? true;
      _alertVibrationEnabled = prefs.getBool(_vibeEnabledKey) ?? true;
      _alertSoundEnabled = prefs.getBool(_soundEnabledKey) ?? true;
      _alertVoiceEnabled = prefs.getBool(_voiceEnabledKey) ?? false;
      debugPrint(
        '[AppSettings] Loaded extended settings: '
        'distance=$_alertDistance, types=$_enabledAlertTypes, '
        'notif=$_alertNotificationEnabled, vibe=$_alertVibrationEnabled, '
        'sound=$_alertSoundEnabled, voice=$_alertVoiceEnabled',
      );
    } catch (e) {
      debugPrint('[AppSettings] Failed to load extended settings: $e');
    }
    notifyListeners();
  }

  /// Reset to default (mainly for testing).
  Future<void> reset() async {
    await setProximityThreshold(defaultThreshold);
    await setAlertDistance(defaultAlertDistance);
    await Future.wait([
      setAlertNotificationEnabled(true),
      setAlertVibrationEnabled(true),
      setAlertSoundEnabled(true),
      setAlertVoiceEnabled(false),
    ]);
    _enabledAlertTypes = defaultEnabledTypes;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_enabledTypesKey);
    } catch (_) {}
    notifyListeners();
  }
}
