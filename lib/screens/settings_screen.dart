import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import '../services/app_settings.dart';
import '../services/permission_service.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import '../widgets/update_dialog.dart';
import '../widgets/section_header.dart';
import '../widgets/threshold_input.dart';
import '../widgets/avatar_picker.dart';
import '../widgets/snooze_card.dart';
import '../widgets/sound_selector.dart';
import '../widgets/system_alert_card.dart';
import '../widgets/proximity_alert_settings.dart';
import '../widgets/appearance_settings.dart';
import '../services/theme_service.dart';
import '../services/foreground_screen_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import 'health_dashboard.dart';
import 'group_screen.dart';
import 'map_screen.dart';
import 'chat_screen.dart';
import 'blacklist_screen.dart';
import 'admin_panel_screen.dart';
import 'stats_screen.dart';
import '../services/admin_service.dart';

/// Settings screen with proximity threshold selector and leave-group action.
/// All settings are ephemeral — stored only in the in-memory AppSettings singleton.
class SettingsScreen extends StatefulWidget {
  final String groupCode;
  final String userName;

  const SettingsScreen({
    super.key,
    required this.groupCode,
    required this.userName,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final LocalStorageService _localStorage = LocalStorageService();
  final AppSettings _appSettings = AppSettings();
  final PermissionService _permissionService = PermissionService();

  bool _isLeaving = false;
  bool _systemAlertGranted = false;
  late String _userName;
  String _myIcon = '🧑';

  // ── Update state ──
  String _currentVersion = '';
  String _firebaseVersion = '';
  bool _isLoadingDashboard = false;

  @override
  void initState() {
    super.initState();
    ForegroundScreenService().set(ForegroundScreen.settings);
    _userName = widget.userName;
    _checkSystemAlert();
    _loadDashboard();
    _loadIcon();
  }

  @override
  void dispose() {
    ForegroundScreenService().clear(ForegroundScreen.settings);
    super.dispose();
  }

  Future<void> _loadIcon() async {
    final icon = await _localStorage.getUserIcon();
    if (mounted) setState(() => _myIcon = icon ?? '🧑');
  }

  Future<void> _checkSystemAlert() async {
    final granted = await _permissionService.isSystemAlertWindowGranted();
    if (mounted) setState(() => _systemAlertGranted = granted);
  }

  Future<void> _sendTestNotification() async {
    final notifService = NotificationService();
    await notifService.initialize();
    await notifService.sendTestNotification(
      playSound: _appSettings.alertSoundEnabled,
      enableVibration: _appSettings.alertVibrationEnabled,
      enableVoice: _appSettings.alertVoiceEnabled,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم إرسال الإشعار الاختباري'),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _testVibration() async {
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    HapticFeedback.mediumImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم اختبار الاهتزاز'),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoadingDashboard = true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
    } catch (_) {}

    try {
      final db = FirebaseDatabase.instance.ref();
      final snap = await db.child('app_version').get();
      if (snap.exists) {
        final data = snap.value is Map
            ? snap.value as Map<dynamic, dynamic>
            : null;
        if (data != null) {
          _firebaseVersion = data['latest_version'] as String? ?? '';
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingDashboard = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 0,
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Redesigned Header ──
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.settings_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'الإعدادات',
                            style: AppTypography.titleMd,
                          ),
                          Text(
                            'إدارة حسابك وإعدادات التطبيق',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.ink500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Profile Hero Card ──
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: AppColors.shadowGlowPrimary,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          _myIcon,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName,
                            style: AppTypography.titleLg.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'المجموعة: ${widget.groupCode}',
                            style: AppTypography.bodySm.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Edit name button
                    Material(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _showChangeNameDialog,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Settings Sections ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'حد الإشعار'),
          ThresholdInput(appSettings: _appSettings),
          const SizedBox(height: 24),
          SectionHeader(title: 'الأيقونة'),
          AvatarPicker(
            localStorage: _localStorage,
            firebaseService: _firebaseService,
            groupCode: widget.groupCode,
          ),
          const SizedBox(height: 24),
          SectionHeader(title: 'الإشعارات'),
          SnoozeCard(localStorage: _localStorage),
          const SizedBox(height: 12),
          SoundSelector(localStorage: _localStorage),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openAppNotificationSettings(context),
              icon: const Icon(Icons.tune_rounded, size: 20),
              label: const Text('إعدادات الإشعارات'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _sendTestNotification(),
              icon: const Icon(Icons.notifications_active_rounded, size: 20),
              label: const Text('إرسال إشعار اختباري'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _testVibration(),
              icon: const Icon(Icons.vibration_rounded, size: 20),
              label: const Text('اختبار الاهتزاز'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(title: 'المظهر'),
          AppearanceSettings(
            appSettings: _appSettings,
            themeService: ThemeService(),
            onChanged: () {},
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HealthDashboard(),
                ),
              ),
              icon: const Icon(Icons.monitor_heart_rounded, size: 20),
              label: const Text('لوحة الصحة'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StatsScreen()),
                );
              },
              icon: const Icon(Icons.bar_chart_rounded, size: 20),
              label: const Text('إحصائيات اليوم'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(title: 'وضع المشرف'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AdminService().isAdmin
                  ? Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: Colors.amber,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('وضع المشرف نشط', style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        )),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdminPanelScreen(
                                    groupCode: widget.groupCode,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.admin_panel_settings_rounded, size: 20),
                            label: const Text('فتح لوحة المشرف'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() => AdminService().logout());
                            },
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('تسجيل الخروج من وضع المشرف'),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showAdminCodeDialog(),
                        icon: const Icon(Icons.lock_rounded, size: 20),
                        label: const Text('تفعيل وضع المشرف'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(title: 'تنبيهات النقاط'),
          ProximityAlertSettings(appSettings: _appSettings),
          const SizedBox(height: 24),
          SectionHeader(title: 'التحديثات'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_isLoadingDashboard)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.system_update_rounded,
                              color: theme.colorScheme.secondary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'التطبيق',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _infoChip(
                            'الإصدار الحالي',
                            'v$_currentVersion',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _infoChip(
                            'آخر إصدار',
                            _firebaseVersion.isNotEmpty
                                ? 'v$_firebaseVersion'
                                : '—',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _checkForUpdate(context),
                        icon: const Icon(Icons.system_update_rounded, size: 20),
                        label: const Text('التحقق من التحديثات'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(title: 'الظهور فوق التطبيقات'),
          SystemAlertCard(
            granted: _systemAlertGranted,
            permissionService: _permissionService,
            onChanged: (v) => setState(() => _systemAlertGranted = v),
          ),
          const SizedBox(height: 24),
          SectionHeader(title: 'المجموعة'),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.logout_rounded,
                      color: theme.colorScheme.error,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'مغادرة المجموعة',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'سيتم حذف موقعك فوراً من المجموعة',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isLeaving ? null : _showLeaveConfirmation,
                      icon: _isLeaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.exit_to_app_rounded, size: 20),
                      label: const Text('مغادرة المجموعة'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ──────────────────── Leave Group ────────────────────

  void _showLeaveConfirmation() {
    AppBottomSheet.showActions<void>(
      context,
      title: 'تأكيد المغادرة',
      subtitle: 'هل أنت متأكد أنك تريد مغادرة المجموعة؟',
      actions: [
        SheetAction(
          label: 'مغادرة المجموعة',
          icon: Icons.logout_rounded,
          isDestructive: true,
          onTap: _leaveGroup,
        ),
        SheetAction(
          label: 'إلغاء',
          icon: Icons.close_rounded,
          iconColor: AppColors.ink700,
          backgroundColor: AppColors.ink50,
          onTap: () {},
        ),
      ],
    );
  }

  Future<void> _openAppNotificationSettings(BuildContext context) async {
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: <String, dynamic>{
          'android.provider.extra.APP_PACKAGE': 'com.glovo_mate.app',
        },
      );
      await intent.launch();
    } catch (e) {
      debugPrint('[Settings] Notification settings failed: $e');
      try {
        final intent = AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:com.glovo_mate.app',
        );
        await intent.launch();
      } catch (e2) {
        debugPrint('[Settings] App details also failed: $e2');
      }
    }
  }

  Future<void> _showChangeNameDialog() async {
    final controller = TextEditingController(text: _userName);
    final newName = await AppBottomSheet.show<String>(
      context,
      title: 'تغيير الاسم',
      subtitle: 'سيظهر الاسم الجديد لجميع أعضاء المجموعة',
      initialChildSize: 0.45,
      minChildSize: 0.4,
      maxChildSize: 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppInput(
            controller: controller,
            label: 'الاسم الجديد',
            leadingIcon: Icons.person_outline_rounded,
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'حفظ التغيير',
            leadingIcon: Icons.check_rounded,
            onPressed: () => Navigator.pop(context, controller.text.trim()),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != _userName) {
      await _firebaseService.updateUserName(
        groupCode: widget.groupCode,
        newName: newName,
      );
      await _localStorage.saveUserName(newName);
      if (mounted) setState(() => _userName = newName);
    }
  }

  Future<void> _showAdminCodeDialog() async {
    final theme = Theme.of(context);
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.amber, size: 22),
              ),
              const SizedBox(width: 12),
              Text('وضع المشرف', style: theme.textTheme.titleLarge),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textAlign: TextAlign.center,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'رمز المشرف',
              hintText: 'أدخل الرمز',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    if (code != null && code.isNotEmpty) {
      if (AdminService().verifyCode(code)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('✓ تم تفعيل وضع المشرف'),
              backgroundColor: Colors.amber.shade700,
            ),
          );
          setState(() {});
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('✗ رمز غير صحيح'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    final theme = Theme.of(context);
    final updateService = UpdateService();
    final info = await updateService.checkForUpdate();
    if (!context.mounted) return;
    if (info.updateAvailable) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => UpdateDialog(
          info: info,
          updateService: updateService,
          onDismiss: () {},
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('التطبيق محدث لأحدث إصدار ✓'),
          backgroundColor: theme.colorScheme.tertiary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _infoChip(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveGroup() async {
    setState(() => _isLeaving = true);

    try {
      // 1. Remove user node from Firebase immediately
      await _firebaseService.removeUserFromGroup(widget.groupCode);
    } catch (_) {
      // Continue even if removal fails — user is leaving anyway
    }

    // 2. Clear the saved session so the user sees the entry form next launch.
    await _localStorage.clearSession();

    if (mounted) {
      // 3. Navigate back to group screen, clearing the entire stack
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const GroupScreen()),
        (_) => false,
      );
    }
  }

  Widget _buildBottomNav() {
    return AppBottomNav(
      selectedIndex: 3,
      onDestinationSelected: (index) {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MapScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 2) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BlacklistScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        }
      },
    );
  }
}
