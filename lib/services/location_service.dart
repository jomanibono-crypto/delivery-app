import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../main.dart' show kLocationInterval;

/// Custom error indicating the device's GPS/location service is turned off.
class GpsDisabledException implements Exception {
  final String message;
  GpsDisabledException([this.message = 'يرجى تفعيل خدمة الموقع (GPS)']);
  @override
  String toString() => message;
}

/// Handles GPS location tracking with the unified interval ([kLocationInterval]).
///
/// Uses Android-specific settings with an explicit [intervalDuration] so updates
/// arrive on a fixed cadence regardless of whether the device is moving. This
/// is the foreground (UI) stream; the background service has its own identical
/// loop. Both use [kLocationInterval] for a consistent cadence.
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  final _positionController = StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _positionController.stream;
  Position? get currentPosition => _currentPosition;

  /// Whether the device location service (GPS) is currently enabled.
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Open the device's location settings screen so the user can enable GPS.
  Future<void> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }

  /// Android-specific settings shared by both the initial fetch and the
  /// continuous stream so the cadence is identical in both paths.
  ///
  /// - [intervalDuration] forces a fresh fix every [kLocationInterval] (3s).
  /// - [distanceFilter] = 0 so movement is never a gate; the interval alone
  ///   decides when an update is emitted.
  LocationSettings get _locationSettings => AndroidSettings(
    accuracy: LocationAccuracy.high,
    intervalDuration: kLocationInterval,
    distanceFilter: 0,
    foregroundNotificationConfig: null,
  );

  /// Initialize location services and start tracking.
  ///
  /// Throws [GpsDisabledException] specifically when the device GPS is off,
  /// so the caller can react with a friendly dialog. Other failures throw
  /// a plain [Exception] with the underlying message.
  Future<Position> initialize() async {
    // ── Check & request permissions ──
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('تم رفض إذن الوصول إلى الموقع');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('تم رفض إذن الموقع نهائياً — يرجى منحه من الإعدادات');
    }

    // ── Check location service is enabled (GPS) ──
    // Throw a typed exception so the UI can offer an "open settings" action.
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw GpsDisabledException();
    }

    // ── Get initial position ──
    final position = await Geolocator.getCurrentPosition(
      locationSettings: _locationSettings,
    );
    _currentPosition = position;
    _positionController.add(position);

    // ── Start listening for position updates (every 5 seconds) ──
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: _locationSettings,
        ).listen((Position position) {
          _currentPosition = position;
          _positionController.add(position);
        });

    return position;
  }

  /// Stop tracking location.
  void dispose() {
    _positionSubscription?.cancel();
    _positionController.close();
  }
}
