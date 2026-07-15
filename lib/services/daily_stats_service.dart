import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'haversine.dart';

/// Tracks the user's daily distance, driving time, moving time,
/// and stopped time. Resets automatically every 24 hours.
class DailyStatsService {
  static final DailyStatsService _instance = DailyStatsService._internal();
  factory DailyStatsService() => _instance;
  DailyStatsService._internal();

  static const _dateKey = 'stats_date';
  static const _distanceKey = 'stats_distance';
  static const _drivingTimeKey = 'stats_driving_time';
  static const _movingTimeKey = 'stats_moving_time';
  static const _stoppedTimeKey = 'stats_stopped_time';

  double _distanceKm = 0.0;
  int _drivingSec = 0;  // speed >= 2 m/s (~7 km/h)
  int _movingSec = 0;   // 0.5 m/s <= speed < 2 m/s
  int _stoppedSec = 0;  // speed < 0.5 m/s

  double _lastLat = 0.0;
  double _lastLng = 0.0;
  bool _hasLastPos = false;
  int _lastTickMs = 0;

  bool _loaded = false;

  double get distanceKm => _distanceKm;
  int get drivingSec => _drivingSec;
  int get movingSec => _movingSec;
  int get stoppedSec => _stoppedSec;
  int get totalSec => _drivingSec + _movingSec + _stoppedSec;

  String get distanceFormatted => '${_distanceKm.toStringAsFixed(1)} كم';
  String get drivingFormatted => _formatDuration(_drivingSec);
  String get movingFormatted => _formatDuration(_movingSec);
  String get stoppedFormatted => _formatDuration(_stoppedSec);
  String get totalFormatted => _formatDuration(totalSec);

  static String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '$hس $mد';
    if (m > 0) return '$mد $sث';
    return '$sث';
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_dateKey) ?? '';
    final today = _todayDate();

    if (savedDate != today) {
      _distanceKm = 0.0;
      _drivingSec = 0;
      _movingSec = 0;
      _stoppedSec = 0;
      await _save(prefs);
    } else {
      _distanceKm = prefs.getDouble(_distanceKey) ?? 0.0;
      _drivingSec = prefs.getInt(_drivingTimeKey) ?? 0;
      _movingSec = prefs.getInt(_movingTimeKey) ?? 0;
      _stoppedSec = prefs.getInt(_stoppedTimeKey) ?? 0;
    }
    _loaded = true;
    debugPrint('[DailyStats] Loaded: ${_distanceKm.toStringAsFixed(1)}km, '
        'drive=${_drivingSec}s move=${_movingSec}s stop=${_stoppedSec}s');
  }

  /// Called on each location update (every ~3s).
  void updatePosition(double lat, double lng, double speedMs) async {
    if (!_loaded) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Distance from last position
    if (_hasLastPos && _lastLat != 0.0 && _lastLng != 0.0 &&
        lat != 0.0 && lng != 0.0) {
      final distM = calculateDistance(_lastLat, _lastLng, lat, lng);
      // Cap at 200m per tick to filter GPS noise
      if (distM > 0 && distM < 200) {
        _distanceKm += distM / 1000.0;
      }
    }
    _lastLat = lat;
    _lastLng = lng;
    _hasLastPos = true;

    // Time accumulation (only if enough time has passed)
    if (_lastTickMs > 0 && speedMs >= 0) {
      final dtSec = (now - _lastTickMs) ~/ 1000;
      if (dtSec > 0 && dtSec < 10) {
        if (speedMs < 0.5) {
          _stoppedSec += dtSec;
        } else if (speedMs < 2.0) {
          _movingSec += dtSec;
        } else {
          _drivingSec += dtSec;
        }
      }
    }
    _lastTickMs = now;

    // Persist every 10 ticks (~30s)
    if (now % 30000 < 3000) {
      await _save(await SharedPreferences.getInstance());
    }
  }

  Future<void> _save(SharedPreferences prefs) async {
    await prefs.setString(_dateKey, _todayDate());
    await prefs.setDouble(_distanceKey, _distanceKm);
    await prefs.setInt(_drivingTimeKey, _drivingSec);
    await prefs.setInt(_movingTimeKey, _movingSec);
    await prefs.setInt(_stoppedTimeKey, _stoppedSec);
  }

  String _todayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Force-save the current stats (e.g. on dispose).
  Future<void> flush() async {
    await _save(await SharedPreferences.getInstance());
  }
}
