import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'local_storage_service.dart';

/// Result of a permission check / request flow.
class PermissionResult {
  final bool locationAlwaysGranted;
  final bool batteryOptimizationIgnored;
  final bool gpsEnabled;

  PermissionResult({
    required this.locationAlwaysGranted,
    required this.batteryOptimizationIgnored,
    required this.gpsEnabled,
  });

  /// True only when ALL three conditions are satisfied. When this is true,
  /// the permission dialog should NEVER be shown.
  bool get allSatisfied =>
      locationAlwaysGranted && batteryOptimizationIgnored && gpsEnabled;
}

/// Manages "Always" location permission and battery optimization dialogs.
///
/// IMPORTANT (lifecycle-safe design):
/// This service NEVER holds a reference to BuildContext across an await that
/// could send the user to a system Settings screen. Every dialog is shown
/// using a context that is checked with `context.mounted` immediately before
/// use, and the long-running intent (opening Settings) does NOT capture or
/// reuse the context afterwards.
class PermissionService {
  /// Silently check ALL three conditions needed for reliable background
  /// tracking. No dialogs, no prompts. Safe to call on every app open.
  ///
  /// Returns a [PermissionResult] where [PermissionResult.allSatisfied] is
  /// true only when:
  ///  - "Always" location permission is granted
  ///  - Battery optimization is disabled (app is whitelisted)
  ///  - Device GPS/location service is turned on
  Future<PermissionResult> checkCurrentStatus() async {
    bool locGranted = false;
    bool batIgnored = false;
    bool gpsOn = false;

    try {
      locGranted = (await Permission.locationAlways.status).isGranted;
    } catch (_) {}
    try {
      batIgnored =
          (await Permission.ignoreBatteryOptimizations.status).isGranted;
    } catch (_) {}
    try {
      gpsOn = await Geolocator.isLocationServiceEnabled();
    } catch (_) {}

    return PermissionResult(
      locationAlwaysGranted: locGranted,
      batteryOptimizationIgnored: batIgnored,
      gpsEnabled: gpsOn,
    );
  }

  /// Entry point called by the home screen. Performs a SILENT check first.
  ///
  /// - If everything is already satisfied → returns immediately, NO dialog.
  /// - If something is missing → shows the explanation dialog once, then
  ///   requests only the things that are actually missing.
  ///
  /// The dialog is therefore shown at most until the user grants everything.
  Future<PermissionResult> requestBackgroundPermissions({
    required BuildContext context,
  }) async {
    // ── SILENT PRE-CHECK ──
    // If all three conditions are already met, never show the dialog.
    final current = await checkCurrentStatus();
    if (current.allSatisfied) {
      debugPrint('[Perm] All permissions already satisfied — skipping dialog.');
      return current;
    }

    debugPrint(
      '[Perm] Missing something: '
      'locAlways=${current.locationAlwaysGranted}, '
      'battery=${current.batteryOptimizationIgnored}, '
      'gps=${current.gpsEnabled}',
    );

    // ── Friendly explanation dialog (cancelable) ──
    final proceed = await _showExplanationDialog(context, current);
    if (!proceed) {
      // User declined — return current status without crashing.
      return checkCurrentStatus();
    }

    // ── Request only what's actually missing ──
    if (!context.mounted) return checkCurrentStatus();

    if (!current.locationAlwaysGranted) {
      await _requestAlwaysLocation(context);
    }
    if (!context.mounted) return checkCurrentStatus();

    if (!current.batteryOptimizationIgnored) {
      await _requestBatteryOptimization(context);
    }

    // PART 4: one-time popup-notification permission (for Xiaomi/Redmi).
    if (!context.mounted) return checkCurrentStatus();
    await _requestPopupNotification(context);

    // Re-check status. The real check happens again on app resume.
    return checkCurrentStatus();
  }

  // ──────────────────── Explanation Dialog ────────────────────

  /// Shows a dialog that only mentions the things actually missing,
  /// so a returning user (who granted most things) sees a concise prompt.
  Future<bool> _showExplanationDialog(
    BuildContext context,
    PermissionResult status,
  ) async {
    if (!context.mounted) return false;

    // Build the list of missing items to display.
    final missing = <Widget>[];
    if (!status.locationAlwaysGranted) {
      missing.add(const _PermissionItem(
        icon: Icons.location_on,
        title: 'الموقع دائماً',
        description: 'يتيح تتبع موقعك حتى عندما يكون التطبيق مغلقاً',
      ));
    }
    if (!status.batteryOptimizationIgnored) {
      missing.add(const _PermissionItem(
        icon: Icons.battery_charging_full,
        title: 'إيقاف تحسين البطارية',
        description: 'يمنع النظام من إغلاق التطبيق في الخلفية',
      ));
    }
    if (!status.gpsEnabled) {
      missing.add(const _PermissionItem(
        icon: Icons.gps_off,
        title: 'تفعيل خدمة الموقع (GPS)',
        description: 'خدمة الموقع معطّلة حالياً على الجهاز',
      ));
    }

    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF1565C0)),
              SizedBox(width: 10),
              Text('الأذونات المطلوبة'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'لكي يعمل التطبيق بشكل صحيح في الخلفية ويُنبّهك عند اقتراب عضو من المجموعة، يحتاج:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ...missing,
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لاحقاً'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    ).then((value) => value ?? false);
  }

  // ──────────────────── Location: Always ────────────────────

  Future<void> _requestAlwaysLocation(BuildContext context) async {
    try {
      final status = await Permission.locationAlways.status;

      if (status.isGranted) {
        debugPrint('[Perm] Location "Always" already granted.');
        return;
      }

      final result = await Permission.locationAlways.request();
      if (result.isGranted) {
        debugPrint('[Perm] Location "Always" granted.');
      } else {
        debugPrint('[Perm] Location "Always" denied: $result');
        _showLocationWarning(context);
      }
    } catch (e) {
      debugPrint('[Perm] Error requesting location always: $e');
    }
  }

  /// Show a warning that background notifications won't be reliable.
  void _showLocationWarning(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '⚠️ تم منح الموقع "أثناء الاستخدام" فقط — لن تعمل إشعارات القرب عندما يكون التطبيق مغلقاً.',
          textAlign: TextAlign.right,
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ──────────────────── Battery Optimization ────────────────────

  Future<void> _requestBatteryOptimization(BuildContext context) async {
    try {
      final isIgnoring = await Permission.ignoreBatteryOptimizations.isGranted;
      if (isIgnoring) {
        debugPrint('[Perm] Battery optimization already ignored.');
        return;
      }

      if (!context.mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.battery_alert, color: Colors.orange),
                SizedBox(width: 10),
                Text('تحسين البطارية'),
              ],
            ),
            content: const Text(
              'لضمان عدم إغلاق التطبيق في الخلفية، يجب تعطيل "تحسين البطارية" و"توفير الطاقة" لهذا التطبيق في إعدادات النظام.\n\n'
              '• في شاشة الإعدادات التي ستفتح، ابحث عن:\n'
              '  - "تحسين البطارية" ← اختَر "لا تقيّد"\n'
              '  - "توفير الطاقة" ← عطّله\n'
              '  - "الإدارة التلقائية" ← عطّلها (لأجهزة Xiaomi)\n\n'
              'سيُفتح لك إعداد النظام الآن.',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('تخطي'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('فتح الإعدادات'),
              ),
            ],
          ),
        ),
      ).then((value) => value ?? false);

      if (!proceed) return;

      // ── Step 1: Try REQUEST_IGNORE_BATTERY_OPTIMIZATIONS ──
      bool opened = false;
      try {
        final intent = AndroidIntent(
          action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
          data: 'package:com.example.glovo_mate',
        );
        await intent.launch();
        debugPrint('[Perm] REQUEST_IGNORE_BATTERY_OPTIMIZATIONS opened.');
        opened = true;
        // Wait a moment then fallback to app details
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[Perm] REQUEST_IGNORE_BATTERY_OPTIMIZATIONS failed: $e');
      }

      // ── Step 2: Always open app details (more comprehensive battery options) ──
      try {
        final intent = AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:com.example.glovo_mate',
        );
        await intent.launch();
        debugPrint('[Perm] App battery details opened.');
      } catch (e) {
        debugPrint('[Perm] Could not open app details: $e');
      }
    } catch (e) {
      debugPrint('[Perm] Battery optimization error: $e');
    }
  }

  // ──────────────────── Popup Notification (PART 4) ────────────────────

  /// One-time dialog asking the user to enable "Display pop-up notifications"
  /// (required on Xiaomi/Redmi for heads-up banners). Only shows once.
  Future<void> _requestPopupNotification(BuildContext context) async {
    final storage = LocalStorageService();
    if (await storage.wasPopupNotifRequested()) return; // already shown once
    if (!context.mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.notifications_active, color: Color(0xFF1565C0)),
              SizedBox(width: 10),
              Text('تفعيل الإشعارات المنبثقة'),
            ],
          ),
          content: const Text(
            'لكي تظهر إشعارات "صاحبك قريب" فوق التطبيقات الأخرى، '
            'يجب تفعيل "إشعارات النوافذ المنبثقة" من إعدادات التطبيق.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لاحقاً'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('فتح الإعدادات'),
            ),
          ],
        ),
      ),
    ).then((v) => v ?? false);

    // Mark as shown regardless of choice (one-time only).
    await storage.setPopupNotifRequested(true);

    if (!proceed || !context.mounted) return;

    // Open the app's notification settings page.
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: <String, dynamic>{
          'android.provider.extra.APP_PACKAGE': 'com.example.glovo_mate',
        },
      );
      await intent.launch();
      debugPrint('[Perm] App notification settings opened.');
    } catch (e) {
      // Fallback: open the app details page (works on Xiaomi/Redmi).
      debugPrint('[Perm] Notification settings failed, trying app details: $e');
      try {
        final intent = AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:com.example.glovo_mate',
        );
        await intent.launch();
      } catch (e2) {
        debugPrint('[Perm] App details also failed: $e2');
      }
    }
  }

  // ──────────────────── SYSTEM_ALERT_WINDOW (PART 5) ────────────────────

  /// Check whether "Draw over other apps" permission is currently granted.
  Future<bool> isSystemAlertWindowGranted() async {
    try {
      return await Permission.systemAlertWindow.status.isGranted;
    } catch (e) {
      debugPrint('[Perm] systemAlertWindow check failed: $e');
      return false;
    }
  }

  /// Request "Draw over other apps" permission (SYSTEM_ALERT_WINDOW).
  ///
  /// On most devices this opens a system dialog. On Xiaomi/Redmi/Huawei it
  /// may redirect to the app's system settings page instead. Returns true
  /// if the permission was granted, false otherwise.
  ///
  /// Safe to call multiple times — the user can retry from Settings.
  Future<bool> requestSystemAlertWindow(BuildContext context) async {
    try {
      final status = await Permission.systemAlertWindow.status;

      if (status.isGranted) {
        debugPrint('[Perm] SYSTEM_ALERT_WINDOW already granted.');
        return true;
      }

      // On some ROMs the direct request doesn't work; show a dialog first.
      if (!context.mounted) return false;

      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.layers, color: Color(0xFF1565C0)),
                SizedBox(width: 10),
                Text('الظهور فوق التطبيقات'),
              ],
            ),
            content: const Text(
              'لكي تظهر إشعارات "صاحبك قريب" كتنبيه منبثق فوق أي تطبيق آخر '
              '(مثل يوتيوب، واتساب، وغيره)، يجب منح صلاحية "الظهور فوق التطبيقات".\n\n'
              'سيُطلب منك الإذن الآن — يرجى الموافقة عليه.',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لاحقاً'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('طلب الإذن'),
              ),
            ],
          ),
        ),
      ).then((v) => v ?? false);

      if (!proceed) return false;
      if (!context.mounted) return false;

      final result = await Permission.systemAlertWindow.request();

      if (result.isGranted) {
        debugPrint('[Perm] SYSTEM_ALERT_WINDOW granted.');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم منح صلاحية الظهور فوق التطبيقات'),
              backgroundColor: Color(0xFF2E7D32),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return true;
      }

      // If denied (or "don't ask again"), open system settings.
      debugPrint('[Perm] SYSTEM_ALERT_WINDOW denied: $result');
      if (!context.mounted) return false;

      final openSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.settings, color: Colors.orange),
                SizedBox(width: 10),
                Text('فتح الإعدادات'),
              ],
            ),
            content: const Text(
              'لم يتم منح الصلاحية. يمكنك تفعيل "الظهور فوق التطبيقات" يدوياً '
              'من إعدادات النظام.',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('فتح الإعدادات'),
              ),
            ],
          ),
        ),
      ).then((v) => v ?? false);

      if (!openSettings || !context.mounted) return false;

      try {
        final intent = AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:com.example.glovo_mate',
        );
        await intent.launch();
        debugPrint('[Perm] App details settings opened for SYSTEM_ALERT_WINDOW.');
      } catch (e) {
        debugPrint('[Perm] Failed to open app details: $e');
      }

      return false;
    } catch (e) {
      debugPrint('[Perm] SYSTEM_ALERT_WINDOW request error: $e');
      return false;
    }
  }
}

/// A styled row widget showing a permission item.
class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF1565C0)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}
