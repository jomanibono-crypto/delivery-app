import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import '../services/update_service.dart';
import 'group_screen.dart';
import 'home_screen.dart';

/// Splash screen that auto-signs in anonymously, checks for updates,
/// then either resumes a saved session (if the group still exists)
/// or navigates to the Group screen for entry.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final UpdateService _updateService = UpdateService();
  final LocalStorageService _localStorage = LocalStorageService();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      await _firebaseService.signInAnonymously();
    } catch (e) {
      if (e is! FirebaseAuthException) rethrow;
    }

    // Check for app updates after auth succeeds
    await _checkForUpdate();

    // Then attempt to resume a saved session
    await _tryResumeSession();
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;

    final updateInfo = await _updateService.checkForUpdate();

    if (!mounted) return;

    if (updateInfo.updateAvailable) {
      _showUpdateDialog(updateInfo);
    }
    // If no update, _tryResumeSession() is called next in _initApp.
  }

  /// Try to resume a previously saved session. If the saved group no
  /// longer exists in Firebase, fall back to the Group entry screen.
  Future<void> _tryResumeSession() async {
    if (!mounted) return;

    final hasSession = await _localStorage.hasSavedSession();
    if (!hasSession) {
      _navigateToGroupScreen();
      return;
    }

    final savedName = await _localStorage.getUserName();
    final savedCode = await _localStorage.getGroupCode();

    if (savedName == null || savedCode == null) {
      _navigateToGroupScreen();
      return;
    }

    // Re-verify the group still exists in Firebase.
    bool groupExists = false;
    try {
      groupExists = await _firebaseService.groupExists(savedCode);
    } catch (e) {
      // If the check fails (network etc.), don't block the user.
      groupExists = false;
    }

    if (!mounted) return;

    if (groupExists) {
      // Resume directly into the group.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            groupCode: savedCode,
            userName: savedName,
          ),
        ),
      );
    } else {
      // Group gone — clear stale data and show entry screen.
      await _localStorage.clearSession();
      _navigateToGroupScreen();
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(
        info: info,
        updateService: _updateService,
        onDismiss: _tryResumeSession,
      ),
    );
  }

  void _navigateToGroupScreen() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const GroupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_rounded,
              size: 80,
              color: Colors.white.withOpacity(0.9),
            ),
            const SizedBox(height: 16),
            const Text(
              'GlovoMate',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'تشارك موقعك مع أصدقائك في الوقت الحقيقي',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// Dialog that shows update info, handles download + install.
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
