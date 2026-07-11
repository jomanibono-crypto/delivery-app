import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Handles camera positioning logic — where to center, what zoom level,
/// and the smart-camera behavior (alone vs group).
class MapCameraService {
  /// Default fallback center (Agadir, Morocco).
  static const LatLng defaultCenter = LatLng(30.4278, -9.5981);
  static const double defaultZoom = 15.5;
  static const double userZoom = 16.0;

  /// Decide center and zoom based on members and user position.
  ///
  /// Returns [center, zoom, shouldDelay].
  /// If [shouldDelay] is true, call [fitToBounds] after 2 seconds.
  static CameraDecision decide({
    required LatLng userPosition,
    required String userId,
    required Map<String, Map<String, dynamic>> members,
  }) {
    // Count other members with valid coordinates
    final others = members.entries.where((e) {
      if (e.key == userId) return false;
      final lat = e.value['lat'] as double? ?? 0.0;
      final lng = e.value['lng'] as double? ?? 0.0;
      return lat != 0.0 && lng != 0.0;
    }).toList();

    if (others.isEmpty) {
      // Case A: alone — center on user
      return CameraDecision(
        center: userPosition,
        zoom: userZoom,
        shouldDelay: false,
      );
    }

    // Case B: group exists — center on user first, then fit
    return CameraDecision(
      center: userPosition,
      zoom: userZoom,
      shouldDelay: true,
    );
  }

  /// Fit the camera to show all members with padding.
  static FitBoundsResult fitToBounds(
    Map<String, Map<String, dynamic>> members,
  ) {
    if (members.isEmpty) {
      return FitBoundsResult(defaultCenter, defaultZoom);
    }

    final positions = <LatLng>[];
    for (final m in members.values) {
      final lat = m['lat'] as double;
      final lng = m['lng'] as double;
      if (lat != 0.0 || lng != 0.0) {
        positions.add(LatLng(lat, lng));
      }
    }

    if (positions.isEmpty) {
      return FitBoundsResult(defaultCenter, defaultZoom);
    }

    if (positions.length == 1) {
      return FitBoundsResult(positions.first, userZoom);
    }

    double minLat = positions.first.latitude;
    double maxLat = positions.first.latitude;
    double minLng = positions.first.longitude;
    double maxLng = positions.first.longitude;

    for (final p in positions) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final span = ((maxLat - minLat).abs() > (maxLng - minLng).abs())
        ? (maxLat - minLat).abs()
        : (maxLng - minLng).abs();

    double zoom;
    if (span > 0.1) {
      zoom = 10;
    } else if (span > 0.05) {
      zoom = 12;
    } else if (span > 0.01) {
      zoom = 14;
    } else {
      zoom = 16;
    }

    debugPrint(
      '[CameraSvc] Fit bounds: center=$center, zoom=$zoom, span=$span',
    );
    return FitBoundsResult(center, zoom);
  }
}

class CameraDecision {
  final LatLng center;
  final double zoom;
  final bool shouldDelay;

  const CameraDecision({
    required this.center,
    required this.zoom,
    required this.shouldDelay,
  });
}

class FitBoundsResult {
  final LatLng center;
  final double zoom;
  const FitBoundsResult(this.center, this.zoom);
}
