import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/app_settings.dart';
import '../services/permission_service.dart';
import '../services/update_service.dart';
import 'group_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'chat_screen.dart';

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

  // ── Publish state ──
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _changelogController = TextEditingController();
  bool _isPublishing = false;
  bool _showManualPublish = false;

  // ── Dashboard state ──
  String _currentVersion = '';
  String _firebaseVersion = '';
  String _firebaseUrl = '';
  String _lastPublishDate = '';
  bool _isTestingUpdate = false;
  bool _isLoadingDashboard = false;
  List<String> _publishHistory = [];

  @override
  void initState() {
    super.initState();
    _checkSystemAlert();
    _loadDashboard();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _changelogController.dispose();
    super.dispose();
  }

  Future<void> _checkSystemAlert() async {
    final granted = await _permissionService.isSystemAlertWindowGranted();
    if (mounted) setState(() => _systemAlertGranted = granted);
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoadingDashboard = true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (_) {}

    try {
      final db = FirebaseDatabase.instance.ref();
      final snap = await db.child('app_version').get();
      if (snap.exists) {
        final data = snap.value as Map<dynamic, dynamic>?;
        if (data != null) {
          _firebaseVersion = data['latest_version'] as String? ?? '---';
          _firebaseUrl = data['download_url'] as String? ?? '';
          _lastPublishDate = data['published_at'] as String? ?? '';
        }
      } else {
        _firebaseVersion = 'غير منشور';
      }
    } catch (_) {
      _firebaseVersion = 'خطأ في الاتصال';
    }

    // Load publish history from shared prefs
    try {
      final prefs = await SharedPreferences.getInstance();
      _publishHistory = prefs.getStringList('publish_history') ?? [];
    } catch (_) {}

    if (mounted) setState(() => _isLoadingDashboard = false);
  }

  Future<void> _testUpdate() async {
    setState(() => _isTestingUpdate = true);
    try {
      final updateService = UpdateService();
      final info = await updateService.checkForUpdate();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(info.updateAvailable ? Icons.system_update : Icons.check_circle,
                  color: info.updateAvailable ? const Color(0xFF1565C0) : Colors.green),
              const SizedBox(width: 10),
              Text(info.updateAvailable ? 'تحديث متاح ✅' : 'لا يوجد تحديث'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dashboardRow('الإصدار الحالي', _currentVersion),
              _dashboardRow('آخر إصدار', info.latestVersion ?? '---'),
              _dashboardRow('الرابط', info.downloadUrl ?? 'بدون رابط',
                  maxLines: 3, mono: true),
              if (info.updateAvailable) ...[
                const SizedBox(height: 12),
                const Text('سيظهر زر التحديث للمستخدمين عند التحقق', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isTestingUpdate = false);
    }
  }

  Widget _dashboardRow(String label, String value, {int maxLines = 1, bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ── Group Info Card ──
          _SectionHeader(title: 'معلومات المجموعة'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.vpn_key_outlined,
                    label: 'كود المجموعة',
                    value: widget.groupCode,
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: 'اسمك',
                    value: widget.userName,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ── Proximity Threshold Card ──
          _SectionHeader(title: 'حد الإشعار'),
          _ThresholdInput(appSettings: _appSettings),
          const SizedBox(height: 28),

          // F1: Avatar / emoji picker
          _SectionHeader(title: 'الأيقونة'),
          _AvatarPicker(
            localStorage: _localStorage,
            firebaseService: _firebaseService,
            groupCode: widget.groupCode,
          ),
          const SizedBox(height: 28),

          // F3: Snooze / mute notifications
          _SectionHeader(title: 'الإشعارات'),
          _SnoozeCard(localStorage: _localStorage),
          const SizedBox(height: 16),

          // PART 2: notification sound selector
          _SoundSelector(localStorage: _localStorage),
          const SizedBox(height: 16),

          // PART 4: open system notification settings (popup permissions)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openAppNotificationSettings(context),
              icon: const Icon(Icons.tune),
              label: const Text('⚙️ إعدادات الإشعارات'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Update Dashboard ──
          _SectionHeader(title: '📦 نظام التحديثات'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoadingDashboard) ...[
                    const Center(child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )),
                  ] else ...[
                    _dashboardRow('إصدار التطبيق', _currentVersion),
                    const Divider(height: 16),
                    _dashboardRow('آخر إصدار منشور', _firebaseVersion),
                    const Divider(height: 16),
                    if (_lastPublishDate.isNotEmpty) ...[
                      _dashboardRow('تاريخ النشر', _lastPublishDate),
                      const Divider(height: 16),
                    ],
                    _dashboardRow('الرابط', _firebaseUrl.isNotEmpty ? _firebaseUrl : 'بدون رابط',
                        maxLines: 2, mono: true),
                    const Divider(height: 16),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 10,
                            color: _firebaseVersion.isNotEmpty && _firebaseVersion != 'خطأ في الاتصال' && _firebaseVersion != 'غير منشور'
                                ? Colors.green : Colors.orange),
                        const SizedBox(width: 6),
                        Text(
                          _firebaseVersion == 'غير منشور' ? '⚠️ لم ينشر تحديث بعد' :
                          _firebaseVersion == 'خطأ في الاتصال' ? '❌ فشل الاتصال بـ Firebase' :
                          '✅ Firebase متصل',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isTestingUpdate ? null : _testUpdate,
                          icon: _isTestingUpdate
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.checklist, size: 18),
                          label: const Text('اختبار التحديث', style: TextStyle(fontSize: 13)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _checkForUpdate(context),
                          icon: const Icon(Icons.system_update, size: 18),
                          label: const Text('التحقق', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Publish history ──
          if (_publishHistory.isNotEmpty) ...[
            _SectionHeader(title: '📜 سجل النشر'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _publishHistory.length; i++)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.circle, size: 8, color: Colors.green[400]),
                      title: Text(_publishHistory[i], style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Manual publish (collapsible fallback) ──
          if (_firebaseService.userId.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _showManualPublish = !_showManualPublish),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(_showManualPublish ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('نشر يدوي', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
            if (_showManualPublish) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          labelText: 'رابط تحميل الـ APK',
                          hintText: 'https://github.com/.../app-release.apk',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.link),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _changelogController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'وصف التحديث',
                          hintText: 'إصلاح الأخطاء وتحسين الأداء',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.description),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isPublishing ? null : () => _publishUpdate(context),
                          icon: _isPublishing
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.cloud_upload),
                          label: Text(_isPublishing ? 'جاري النشر...' : '📤 نشر التحديث'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 28),

          // PART 5: SYSTEM_ALERT_WINDOW — Draw over other apps
          _SectionHeader(title: 'الظهور فوق التطبيقات'),
          _SystemAlertCard(
            granted: _systemAlertGranted,
            permissionService: _permissionService,
            onChanged: (v) => setState(() => _systemAlertGranted = v),
          ),
          const SizedBox(height: 28),

          // ── Leave Group Card ──
          _SectionHeader(title: 'المجموعة'),
          Card(
            elevation: 0,
            color: Colors.red.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.red.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.logout, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'مغادرة المجموعة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'سيتم حذف موقعك فوراً من المجموعة',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
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
                          : const Icon(Icons.exit_to_app),
                      label: const Text('مغادرة المجموعة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ──────────────────── Leave Group ────────────────────

  void _showLeaveConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد المغادرة'),
        content: const Text('هل أنت متأكد أنك تريد مغادرة المجموعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(dialogContext); // close dialog
              _leaveGroup();
            },
            child: const Text('مغادرة'),
          ),
        ],
      ),
    );
  }

  /// PART 4: Open system app notification settings so the user can enable
  /// "Display pop-up notifications" (needed on Xiaomi/Redmi for heads-up).
  Future<void> _openAppNotificationSettings(BuildContext context) async {
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: <String, dynamic>{
          'android.provider.extra.APP_PACKAGE': 'com.example.glovo_mate',
        },
      );
      await intent.launch();
    } catch (e) {
      debugPrint('[Settings] Notification settings failed: $e');
      try {
        final intent = AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: 'package:com.example.glovo_mate',
        );
        await intent.launch();
      } catch (e2) {
        debugPrint('[Settings] App details also failed: $e2');
      }
    }
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    final updateService = UpdateService();
    final info = await updateService.checkForUpdate();
    if (!context.mounted) return;
    if (info.updateAvailable) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _UpdateDialog(
          info: info,
          updateService: updateService,
          onDismiss: () {},
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التطبيق محدث لأحدث إصدار ✅'),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _publishUpdate(BuildContext context) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رابط التحميل'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final parts = packageInfo.version.split('.');
      final patch = int.tryParse(parts.last) ?? 0;
      parts[parts.length - 1] = (patch + 1).toString();
      final nextVersion = parts.join('.');

      final changelog = _changelogController.text.trim().isEmpty
          ? 'إصدار جديد'
          : _changelogController.text.trim();

      final now = DateTime.now();
      final publishDate = now.toIso8601String();

      final db = FirebaseDatabase.instance.ref();
      await db.child('app_version').set({
        'latest_version': nextVersion,
        'download_url': url,
        'changelog': changelog,
        'file_size': 0,
        'published_at': publishDate,
      });

      // Save to publish history
      try {
        final prefs = await SharedPreferences.getInstance();
        final history = prefs.getStringList('publish_history') ?? [];
        history.insert(0, 'v$nextVersion — ${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}');
        if (history.length > 20) history.removeLast(); // keep last 20
        await prefs.setStringList('publish_history', history);
        _publishHistory = history;
      } catch (_) {}

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم نشر الإصدار $nextVersion'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      _urlController.clear();
      _changelogController.clear();
      // Refresh dashboard
      _firebaseVersion = nextVersion;
      _firebaseUrl = url;
      _lastPublishDate = publishDate;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
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

  // ──────────────────── Bottom Nav ────────────────────

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: 2,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'الخريطة'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'الدردشة'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
      ],
      onDestinationSelected: (index) {
        if (index == 0) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MapScreen(groupCode: widget.groupCode, userName: widget.userName)));
        } else if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(groupCode: widget.groupCode, userName: widget.userName)));
        }
      },
    );
  }
}

// ──────────────────── Reusable Widgets ────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A237E),
              ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

/// Custom distance threshold input with validation + persistence.
///
/// Shows a text field pre-filled with the currently saved value, validates
/// the input is a positive integer, and persists it via [AppSettings].
class _ThresholdInput extends StatefulWidget {
  final AppSettings appSettings;

  const _ThresholdInput({required this.appSettings});

  @override
  State<_ThresholdInput> createState() => _ThresholdInputState();
}

class _ThresholdInputState extends State<_ThresholdInput> {
  late final TextEditingController _controller;
  String? _errorText;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the currently saved value (not empty).
    _controller =
        TextEditingController(text: widget.appSettings.proximityThreshold.toString());
    widget.appSettings.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    widget.appSettings.removeListener(_onExternalChange);
    _controller.dispose();
    super.dispose();
  }

  /// Keep the field in sync if the value changes elsewhere (e.g. reset).
  void _onExternalChange() {
    if (!mounted) return;
    final current = widget.appSettings.proximityThreshold.toString();
    if (_controller.text.trim() != current) {
      _controller.text = current;
    }
  }

  Future<void> _save() async {
    final raw = _controller.text.trim();

    // Validate: must be a positive integer.
    final value = int.tryParse(raw);
    if (value == null) {
      setState(() => _errorText = 'أدخل رقماً صحيحاً');
      return;
    }
    if (value <= 0) {
      setState(() => _errorText = 'يجب أن تكون القيمة أكبر من صفر');
      return;
    }
    if (value > 100000) {
      setState(() => _errorText = 'القيمة كبيرة جداً (الحد الأقصى 100كم)');
      return;
    }

    setState(() {
      _errorText = null;
      _saved = false;
    });

    await widget.appSettings.setProximityThreshold(value);

    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الحد: $value متر'),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
        ),
      );
      // Hide the "saved" indicator after a moment.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saved = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appSettings,
      builder: (context, _) {
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مسافة الإشعار عند اقتراب عضو',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Numeric input field ──
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'المسافة (بالمتر)',
                          hintText: 'مثال: 200',
                          errorText: _errorText,
                          suffixText: 'متر',
                          prefixIcon: const Icon(Icons.straighten),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ── Save button ──
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: Icon(_saved ? Icons.check : Icons.save),
                        label: Text(_saved ? 'تم' : 'حفظ'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'الحد الحالي: ${widget.appSettings.proximityThreshold} متر',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// F1: Emoji avatar picker. Lets the user choose an emoji that represents
/// them in the group. Persists locally + syncs to Firebase.
class _AvatarPicker extends StatefulWidget {
  final LocalStorageService localStorage;
  final FirebaseService firebaseService;
  final String groupCode;

  const _AvatarPicker({
    required this.localStorage,
    required this.firebaseService,
    required this.groupCode,
  });

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  String _selected = '🧑';

  static const List<String> _emojiOptions = [
    '🧑', '🚗', '🏍️', '🚲', '🚶', '📦', '🏃', '🛵',
    '🚕', '🚚', '🏠', '🎯', '⭐', '🔵', '🔴',
  ];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await widget.localStorage.getUserIcon();
    if (mounted && saved != null) setState(() => _selected = saved);
  }

  Future<void> _select(String emoji) async {
    setState(() => _selected = emoji);
    await widget.localStorage.saveUserIcon(emoji);
    await widget.firebaseService.updateUserIcon(
      groupCode: widget.groupCode,
      icon: emoji,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم اختيار: $emoji'),
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اختر أيقونة تمثلك في المجموعة',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _emojiOptions.map((emoji) {
                final isSelected = emoji == _selected;
                return GestureDetector(
                  onTap: () => _select(emoji),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1565C0).withOpacity(0.15)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: const Color(0xFF1565C0), width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'الحالي: $_selected',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1565C0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// F3: Snooze / mute notifications for a chosen duration.
class _SnoozeCard extends StatefulWidget {
  final LocalStorageService localStorage;
  const _SnoozeCard({required this.localStorage});

  @override
  State<_SnoozeCard> createState() => _SnoozeCardState();
}

class _SnoozeCardState extends State<_SnoozeCard> {
  int _mutedUntil = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final until = await widget.localStorage.getMutedUntil();
    if (mounted) setState(() => _mutedUntil = until);
  }

  Future<void> _snooze(Duration duration) async {
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await widget.localStorage.setMutedUntil(until);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إيقاف الإشعارات لمدة ${_fmtDuration(duration)}'),
          backgroundColor: const Color(0xFF1565C0),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _fmtDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours} ساعة';
    return '${d.inMinutes} دقيقة';
  }

  Future<void> _cancel() async {
    await widget.localStorage.setMutedUntil(null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isMuted = _mutedUntil > now;

    final endTime = isMuted
        ? DateTime.fromMillisecondsSinceEpoch(_mutedUntil)
        : null;
    final hh = endTime?.hour.toString().padLeft(2, '0') ?? '--';
    final mm = endTime?.minute.toString().padLeft(2, '0') ?? '--';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إيقاف الإشعارات مؤقتاً',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            if (isMuted) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_off, color: Color(0xFF856404)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'متوقفة حتى $hh:$mm',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: Color(0xFF856404),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _cancel,
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                children: [
                  _snoozeButton('15 دقيقة', const Duration(minutes: 15)),
                  _snoozeButton('30 دقيقة', const Duration(minutes: 30)),
                  _snoozeButton('1 ساعة', const Duration(hours: 1)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _snoozeButton(String label, Duration duration) {
    return FilledButton.tonal(
      onPressed: () => _snooze(duration),
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}

/// PART 5: SYSTEM_ALERT_WINDOW permission card.
/// Shows the current status and a button to request the permission.
class _SystemAlertCard extends StatefulWidget {
  final bool granted;
  final PermissionService permissionService;
  final ValueChanged<bool> onChanged;

  const _SystemAlertCard({
    required this.granted,
    required this.permissionService,
    required this.onChanged,
  });

  @override
  State<_SystemAlertCard> createState() => _SystemAlertCardState();
}

class _SystemAlertCardState extends State<_SystemAlertCard> {
  bool _isLoading = false;

  Future<void> _request() async {
    setState(() => _isLoading = true);
    final granted = await widget.permissionService.requestSystemAlertWindow(
      context,
    );
    widget.onChanged(granted);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final granted = widget.granted;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 20,
                  color: granted ? Colors.green : Colors.grey[600],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'الظهور فوق التطبيقات الأخرى',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: granted ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    granted ? 'مفعل' : 'غير مفعل',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: granted ? Colors.green.shade700 : Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              granted
                  ? 'الإشعارات المنبثقة ستعمل فوق أي تطبيق'
                  : 'لظهور إشعارات "صاحبك قريب" فوق التطبيقات الأخرى (يوتيوب، واتساب...)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _request,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(granted ? Icons.check_circle : Icons.layers,
                        color: granted ? Colors.green : null),
                label: Text(
                  granted ? 'تم منح الصلاحية' : 'طلب صلاحية الظهور فوق التطبيقات',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: granted ? Colors.green.shade700 : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: granted ? Colors.green.shade300 : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog shown when an update is available.
class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateService updateService;
  final VoidCallback onDismiss;

  const _UpdateDialog({
    required this.info,
    required this.updateService,
    required this.onDismiss,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _statusText = 'جاري التحميل...';
      _progress = 0.0;
    });

    try {
      final filePath = await widget.updateService.downloadApk(
        url: widget.info.downloadUrl!,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusText = 'جاري التحميل... ${(_progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() => _statusText = 'جاري تثبيت التحديث...');

      final installed = await widget.updateService.installApk(filePath);

      if (!mounted) return;

      if (installed) {
        Navigator.of(context).pop();
        widget.onDismiss();
      } else {
        setState(() {
          _isDownloading = false;
          _statusText = 'فشل في تثبيت التحديث. جرّب مرة أخرى.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _statusText = 'خطأ في التحميل: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.system_update, color: Color(0xFF1565C0)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('إصدار جديد v${info.latestVersion ?? ''}'),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version + Size row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F9FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFF1565C0)),
                const SizedBox(width: 8),
                Text(
                  'الإصدار: v${info.latestVersion ?? '--'}  •  الحجم: ${info.formattedSize}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Changelog
          if ((info.changelog ?? '').isNotEmpty) ...[
            Text(
              'ما الجديد:',
              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              info.changelog!,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 14),
            ),
          ],
          const SizedBox(height: 16),
          // Progress
          if (_isDownloading) ...[
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textDirection: TextDirection.rtl,
            ),
          ] else if (_statusText.isNotEmpty) ...[
            Text(
              _statusText,
              style: const TextStyle(fontSize: 12, color: Colors.red),
              textDirection: TextDirection.rtl,
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDismiss();
            },
            child: const Text('تذكير لاحقاً'),
          ),
        if (!_isDownloading)
          FilledButton.icon(
            onPressed: _downloadAndInstall,
            icon: const Icon(Icons.download),
            label: const Text('تحميل التحديث'),
          ),
      ],
    );
  }
}

/// PART 2: Sound selector for proximity notifications.
class _SoundSelector extends StatefulWidget {
  final LocalStorageService localStorage;
  const _SoundSelector({required this.localStorage});

  @override
  State<_SoundSelector> createState() => _SoundSelectorState();
}

class _SoundSelectorState extends State<_SoundSelector> {
  final NotificationService _notifService = NotificationService();
  String _selected = 'default';
  bool _isLoading = true;

  static const _sounds = [
    ('default', 'افتراضي', '🔔'),
    ('chime1', 'نغمة 1', '🎵'),
    ('chime2', 'نغمة 2', '🎶'),
    ('chime3', 'نغمة 3', '🔊'),
    ('silent', 'صامت', '🔇'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await widget.localStorage.getNotifSound();
    if (mounted) setState(() { _selected = saved; _isLoading = false; });
  }

  Future<void> _select(String key) async {
    setState(() => _selected = key);
    await _notifService.changeSound(key);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم اختيار الصوت'),
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'صوت الإشعار',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sounds.map((s) {
                  final key = s.$1;
                  final label = s.$2;
                  final emoji = s.$3;
                  final isSelected = key == _selected;
                  return GestureDetector(
                    onTap: () => _select(key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF1565C0).withOpacity(0.12)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(color: const Color(0xFF1565C0), width: 2)
                            : Border.all(color: Colors.transparent),
                      ),
                      child: Text('$emoji $label',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                            color:
                                isSelected ? const Color(0xFF1565C0) : Colors.black87,
                          )),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
