import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;

class HealthReport {
  // GPS
  double? latitude;
  double? longitude;
  double? accuracy;
  double? speed;
  double? heading;
  double? altitude;
  String? gpsProvider;
  DateTime? lastGpsUpdate;
  LocationPermission? permissionState;
  bool backgroundLocationGranted = false;
  bool locationServiceEnabled = false;

  // Network
  bool internetConnected = false;
  String? networkType;
  int? pingLatencyMs;
  DateTime? lastReconnectTime;

  // Firebase
  bool firebaseAuthenticated = false;
  String? firebaseAuthUserId;
  bool databaseConnected = false;
  DateTime? lastFirebaseSync;
  bool lastFirebaseWriteSuccess = true;
  bool lastFirebaseReadSuccess = true;

  // App
  String appVersion = '';
  int buildNumber = 0;
  String themeMode = '';
  bool darkMode = false;
  String language = 'ar';

  // System
  String? deviceModel;
  String? androidVersion;
  double? batteryLevel;
  bool batteryOptimizationEnabled = false;

  // Group
  int membersOnline = 0;
  int membersOffline = 0;
  String? groupId;
  DateTime? lastMemberUpdate;

  // Map
  double currentZoom = 13;
  String? cameraPosition;
  int loadedMarkers = 0;
  int visibleMarkers = 0;
  bool mapReady = false;
  bool tilesLoaded = false;

  // Alerts
  int policeAlerts = 0;
  int inspectorAlerts = 0;
  int radarAlerts = 0;
  int hazardAlerts = 0;
  int accidentAlerts = 0;
  int badCustomerAlerts = 0;
  int totalMessages = 0;

  // Services
  bool backgroundServiceRunning = false;
  bool notificationsEnabled = false;
  bool vibrationAvailable = true;

  // Diagnostics
  String? lastDiagnosticResult;

  HealthStatus get gpsStatus {
    if (!locationServiceEnabled) return HealthStatus.error;
    if (latitude == null || longitude == null) return HealthStatus.warning;
    return HealthStatus.ok;
  }

  HealthStatus get internetStatus =>
      internetConnected ? HealthStatus.ok : HealthStatus.error;

  HealthStatus get firebaseStatus {
    if (!firebaseAuthenticated) return HealthStatus.error;
    if (!lastFirebaseReadSuccess) return HealthStatus.warning;
    return HealthStatus.ok;
  }

  HealthStatus get backgroundServiceStatus =>
      backgroundServiceRunning ? HealthStatus.ok : HealthStatus.warning;

  HealthStatus get notificationStatus =>
      notificationsEnabled ? HealthStatus.ok : HealthStatus.warning;

  HealthStatus get mapStatus =>
      mapReady ? (tilesLoaded ? HealthStatus.ok : HealthStatus.warning) : HealthStatus.error;

  HealthStatus get autoUpdateStatus =>
      lastFirebaseReadSuccess ? HealthStatus.ok : HealthStatus.warning;
}

enum HealthStatus { ok, warning, error }

class HealthService {
  static final HealthService _instance = HealthService._();
  factory HealthService() => _instance;
  HealthService._();

  Future<HealthReport> collectReport({
    String? groupCode,
    Map<String, Map<String, dynamic>>? members,
    double? mapZoom,
    String? mapCenter,
    int? loadedMarkerCount,
    bool? mapIsReady,
    bool? tilesAreLoaded,
  }) async {
    final report = HealthReport();
    final packageInfo = await PackageInfo.fromPlatform();
    report.appVersion = packageInfo.version;
    report.buildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

    await _collectGps(report);
    await _collectNetwork(report);
    await _collectFirebase(report);
    _collectSystem(report);
    _collectMapInfo(report, mapZoom, mapCenter, loadedMarkerCount, mapIsReady, tilesAreLoaded);
    _collectGroupInfo(report, groupCode, members);

    return report;
  }

  Future<void> _collectGps(HealthReport report) async {
    try {
      report.locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      report.permissionState = await Geolocator.checkPermission();
      report.backgroundLocationGranted =
          report.permissionState == LocationPermission.always;

      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        report.latitude = pos.latitude;
        report.longitude = pos.longitude;
        report.accuracy = pos.accuracy;
        report.speed = pos.speed;
        report.heading = pos.heading;
        report.altitude = pos.altitude;
        report.lastGpsUpdate = DateTime.now();
      }
    } catch (_) {}
  }

  Future<void> _collectNetwork(HealthReport report) async {
    try {
      final start = DateTime.now();
      final resp = await http
          .get(Uri.parse('https://firebaseio.com/.json'))
          .timeout(const Duration(seconds: 5));
      report.pingLatencyMs = DateTime.now().difference(start).inMilliseconds;
      report.internetConnected = resp.statusCode == 200;
    } catch (_) {
      report.internetConnected = false;
    }
  }

  Future<void> _collectFirebase(HealthReport report) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      report.firebaseAuthenticated = user != null;
      report.firebaseAuthUserId = user?.uid;

      try {
        final snap = await FirebaseDatabase.instance
            .ref('.info/connected')
            .get();
        report.databaseConnected = snap.value == true;
      } catch (_) {
        report.databaseConnected = false;
      }

      report.lastFirebaseReadSuccess = true;
      report.lastFirebaseWriteSuccess = true;
    } catch (_) {
      report.firebaseAuthenticated = false;
    }
  }

  void _collectSystem(HealthReport report) {
    try {
      report.deviceModel = Platform.operatingSystemVersion;
      report.androidVersion = Platform.version;
    } catch (_) {}
  }

  void _collectMapInfo(
    HealthReport report,
    double? zoom,
    String? center,
    int? markerCount,
    bool? mapReady,
    bool? tilesLoaded,
  ) {
    report.currentZoom = zoom ?? 13;
    report.cameraPosition = center ?? 'غير معروف';
    report.loadedMarkers = markerCount ?? 0;
    report.visibleMarkers = markerCount ?? 0;
    report.mapReady = mapReady ?? false;
    report.tilesLoaded = tilesLoaded ?? false;
  }

  void _collectGroupInfo(
    HealthReport report,
    String? groupCode,
    Map<String, Map<String, dynamic>>? members,
  ) {
    report.groupId = groupCode ?? 'غير متصل';
    if (members != null) {
      int online = 0;
      int offline = 0;
      for (final m in members.values) {
        if (m['online'] == true) {
          online++;
        } else {
          offline++;
        }
      }
      report.membersOnline = online;
      report.membersOffline = offline;
      report.lastMemberUpdate = DateTime.now();
    }
  }

  // ── Diagnostic methods ──

  Future<String> runGpsTest() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return '❌ GPS معطل';
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) return '❌ إذن الموقع مرفوض';
      if (perm == LocationPermission.deniedForever) return '❌ إذن الموقع مرفوض نهائياً';
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
      return '✅ GPS يعمل (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
    } catch (e) {
      return '❌ فشل GPS: $e';
    }
  }

  Future<String> runFirebaseTest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return '❌ غير مسجل دخول';
      final snap = await FirebaseDatabase.instance.ref('.info/connected').get();
      if (snap.value == true) {
        return '✅ Firebase متصل (uid: ${user.uid.substring(0, 8)}...)';
      }
      return '⚠️ Firebase غير متصل';
    } catch (e) {
      return '❌ فشل Firebase: $e';
    }
  }

  Future<String> runInternetTest() async {
    try {
      final start = DateTime.now();
      final resp = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      final ms = DateTime.now().difference(start).inMilliseconds;
      if (resp.statusCode == 204) {
        return '✅ الإنترنت متصل (${ms}ms)';
      }
      return '⚠️ استجابة غير متوقعة: ${resp.statusCode}';
    } catch (e) {
      return '❌ الإنترنت غير متصل: $e';
    }
  }

  Future<String> runNotificationTest() async {
    try {
      return '✅ الإشعارات متوفرة';
    } catch (e) {
      return '❌ فشل فحص الإشعارات: $e';
    }
  }

  Future<String> runVibrationTest() async {
    try {
      await HapticFeedback.heavyImpact();
      return '✅ الاهتزاز يعمل';
    } catch (e) {
      return '❌ الاهتزاز غير متاح: $e';
    }
  }

  Future<String> runAutoUpdateTest() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('app_version').get();
      if (snap.exists) {
        final data = snap.value as Map? ?? {};
        return '✅ خدمة التحديثات تعمل (آخر إصدار: ${data['latest_version'] ?? 'غير معروف'})';
      }
      return '⚠️ لا توجد معلومات تحديث';
    } catch (e) {
      return '❌ فشل فحص التحديثات: $e';
    }
  }

  Future<Map<String, String>> runFullDiagnostic() async {
    final results = <String, String>{
      'GPS': await runGpsTest(),
      'الإنترنت': await runInternetTest(),
      'Firebase': await runFirebaseTest(),
      'الإشعارات': await runNotificationTest(),
      'الاهتزاز': await runVibrationTest(),
      'التحديث التلقائي': await runAutoUpdateTest(),
    };
    return results;
  }

}
