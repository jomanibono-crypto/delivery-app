import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Single-responsibility service for retrieving the user's location.
///
/// Caches the last known position to avoid repeated GPS calls.
class MapLocationService {
  static final MapLocationService _instance = MapLocationService._();
  factory MapLocationService() => _instance;
  MapLocationService._();

  LatLng? _cachedPosition;
  LatLng? get cachedPosition => _cachedPosition;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 1. Try last known position (instant, no GPS needed).
  Future<LatLng?> getLastKnownLocation() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        _cachedPosition = LatLng(pos.latitude, pos.longitude);
        debugPrint('[LocationSvc] Last known: $_cachedPosition');
        return _cachedPosition;
      }
    } catch (_) {}
    return null;
  }

  /// 2. Get current GPS position with timeout.
  Future<LatLng?> getCurrentLocation() async {
    _isLoading = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).timeout(const Duration(seconds: 4));
      _cachedPosition = LatLng(pos.latitude, pos.longitude);
      debugPrint('[LocationSvc] Current GPS: $_cachedPosition');
      return _cachedPosition;
    } catch (e) {
      debugPrint('[LocationSvc] GPS failed: $e');
      return null;
    } finally {
      _isLoading = false;
    }
  }

  /// Full location resolution with fallback chain:
  /// last known (instant) → GPS (4s timeout) → null (caller uses Agadir)
  Future<LatLng?> resolve() async {
    final lastKnown = await getLastKnownLocation();
    if (lastKnown != null) return lastKnown;
    return getCurrentLocation();
  }
}
