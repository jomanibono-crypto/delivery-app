import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of an update check.
class UpdateInfo {
  final bool updateAvailable;
  final String? latestVersion;
  final String? downloadUrl;
  final String? changelog;
  final int? fileSize; // in bytes
  final String? apkHash; // SHA-256 hex digest for integrity check

  UpdateInfo({
    required this.updateAvailable,
    this.latestVersion,
    this.downloadUrl,
    this.changelog,
    this.fileSize,
    this.apkHash,
  });

  String get formattedSize {
    if (fileSize == null) return 'غير معروف';
    if (fileSize! >= 1073741824) {
      return '${(fileSize! / 1073741824).toStringAsFixed(1)} GB';
    }
    if (fileSize! >= 1048576) {
      return '${(fileSize! / 1048576).toStringAsFixed(1)} MB';
    }
    if (fileSize! >= 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(0)} KB';
    }
    return '$fileSize B';
  }
}

/// Service that checks Firebase Realtime Database for a newer app version
/// and handles downloading + installing the APK.
class UpdateService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// Read `app_version/` from Firebase and compare against the installed version.
  /// Returns an [UpdateInfo] with updateAvailable = true if a newer version exists.
  Future<UpdateInfo> checkForUpdate() async {
    debugPrint('[UpdateService] Checking for updates...');

    try {
      final snap = await _db.child('app_version').get();

      if (!snap.exists) {
        debugPrint(
          '[UpdateService] No app_version node found in Firebase. Skipping update check.',
        );
        return UpdateInfo(updateAvailable: false);
      }

      final data = snap.value is Map
          ? snap.value as Map<dynamic, dynamic>
          : null;
      if (data == null) {
        return UpdateInfo(updateAvailable: false);
      }

      final latestVersion = data['latest_version'] as String?;
      final downloadUrl = data['download_url'] as String?;
      final changelog = data['changelog'] as String?;
      final fileSize = data['file_size'] as int?;
      final apkHash = data['apk_hash'] as String?;

      if (latestVersion == null || downloadUrl == null) {
        debugPrint(
          '[UpdateService] Incomplete app_version data (missing fields).',
        );
        return UpdateInfo(updateAvailable: false);
      }

      // Get currently installed version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint(
        '[UpdateService] Installed: v$currentVersion | Latest: v$latestVersion',
      );

      final available = _isNewer(latestVersion, currentVersion);

      if (available) {
        debugPrint('[UpdateService] ✓ Update available!');
      } else {
        debugPrint('[UpdateService] App is up to date.');
      }

      return UpdateInfo(
        updateAvailable: available,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        changelog: changelog ?? 'لا توجد تفاصيل متاحة.',
        fileSize: fileSize,
        apkHash: apkHash,
      );
    } catch (e) {
      debugPrint('[UpdateService] Error checking for update: ${e.toString()}');
      return UpdateInfo(updateAvailable: false);
    }
  }

  /// Download the APK from [url], return the local file path.
  /// Shows download progress via [onProgress] callback (0.0 – 1.0).
  /// If [expectedHash] is provided, verifies the SHA-256 hash after download.
  Future<String> downloadApk({
    required String url,
    void Function(double progress)? onProgress,
    String? expectedHash,
  }) async {
    debugPrint('[UpdateService] Downloading APK from: $url');

    // Use a single HttpClient with explicit redirect following
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.followRedirects = true;
      request.maxRedirects = 10;

      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/glovo_mate_update.apk');
      final sink = file.openWrite();

      int downloadedBytes = 0;

      await response.stream
          .listen(
            (chunk) {
              downloadedBytes += chunk.length;
              sink.add(chunk);
              if (totalBytes != null &&
                  totalBytes > 0 &&
                  onProgress != null) {
                onProgress(downloadedBytes / totalBytes);
              }
            },
            onDone: sink.close,
            onError: (e) {
              sink.close();
              throw Exception('Download stream error: ${e.toString()}');
            },
          )
          .asFuture();

      debugPrint('[UpdateService] APK downloaded to: ${file.path}');

      if (expectedHash != null && expectedHash.isNotEmpty) {
        final bytes = await file.readAsBytes();
        final hashBytes = sha256.convert(bytes);
        final computedHash = hashBytes.toString();
        if (computedHash != expectedHash.toLowerCase()) {
          await file.delete();
          throw Exception(
            'SHA-256 mismatch. Expected: $expectedHash, Computed: $computedHash',
          );
        }
        debugPrint('[UpdateService] SHA-256 verified successfully.');
      }

      return file.path;
    } finally {
      client.close();
    }
  }

  /// Request install permission (Android 8+), then open the APK file.
  Future<bool> installApk(String filePath) async {
    debugPrint('[UpdateService] Requesting install permission...');

    final status = await Permission.requestInstallPackages.status;
    if (!status.isGranted) {
      final result = await Permission.requestInstallPackages.request();
      if (!result.isGranted) {
        debugPrint('[UpdateService] Install permission denied.');
        return false;
      }
    }

    debugPrint('[UpdateService] Opening APK installer: $filePath');
    final result = await OpenFilex.open(filePath);
    debugPrint(
      '[UpdateService] OpenFilex result: ${result.type} — ${result.message}',
    );
    return result.type == ResultType.done;
  }

  /// Compare two version strings (e.g. "1.0.1" vs "1.0.0").
  /// Returns true if [latest] > [current].
  bool _isNewer(String latest, String current) {
    final latestParts = latest.split('.').map(int.parse).toList();
    final currentParts = current.split('.').map(int.parse).toList();

    // Pad shorter list with zeros
    while (latestParts.length < currentParts.length) {
      latestParts.add(0);
    }
    while (currentParts.length < latestParts.length) {
      currentParts.add(0);
    }

    for (var i = 0; i < latestParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }

    return false; // equal versions
  }
}
