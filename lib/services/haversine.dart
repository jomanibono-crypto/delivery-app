import 'dart:math';

/// Calculate the distance in meters between two GPS coordinates
/// using the Haversine formula.
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0; // meters

  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);

  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);

  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadius * c;
}

/// Calculate the initial bearing (compass direction) in degrees from point 1
/// to point 2. Result is in [0, 360), where 0 = north, 90 = east, etc.
///
/// Used to rotate a directional arrow pointing toward each member.
double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
  final lat1Rad = _toRadians(lat1);
  final lat2Rad = _toRadians(lat2);
  final dLon = _toRadians(lon2 - lon1);

  final y = sin(dLon) * cos(lat2Rad);
  final x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

  final theta = atan2(y, x);
  final degrees = _toDegrees(theta);
  // Normalize to [0, 360)
  return (degrees + 360) % 360;
}

double _toRadians(double degrees) => degrees * pi / 180;
double _toDegrees(double radians) => radians * 180 / pi;
