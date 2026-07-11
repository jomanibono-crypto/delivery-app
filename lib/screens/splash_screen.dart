import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';
import 'group_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  final Color accentColor;
  const SplashScreen({super.key, required this.accentColor});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebaseService = FirebaseService();
  final UpdateService _updateService = UpdateService();
  final LocalStorageService _localStorage = LocalStorageService();
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  bool _hasError = false;
  String _errorMessage = '';
  Timer? _initTimeout;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeIn),
    );
    _animController.forward();
    _startInit();
  }

  @override
  void dispose() {
    _animController.dispose();
    _initTimeout?.cancel();
    super.dispose();
  }

  void _startInit() {
    // Safety timeout — if init takes more than 20s, show error
    _initTimeout = Timer(const Duration(seconds: 20), () {
      if (mounted && !_hasError) {
        setState(() {
          _hasError = true;
          _errorMessage = 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
        });
      }
    });
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      await _firebaseService.signInAnonymously().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Firebase auth timed out'),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is TimeoutException || e is FirebaseAuthException) {
        setState(() {
          _hasError = true;
          _errorMessage = 'تعذّر تسجيل الدخول. تحقق من اتصالك بالإنترنت.';
        });
        return;
      }
    }
    if (!mounted) return;
    await _checkForUpdate();
    if (!mounted) return;
    await _tryResumeSession();
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    try {
      final updateInfo = await _updateService.checkForUpdate().timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('Update check timed out'),
      );
      if (!mounted) return;
      if (updateInfo.updateAvailable) {
        _showUpdateDialog(updateInfo);
        return;
      }
    } catch (_) {
      // Silently skip update check on failure — not critical for startup
    }
  }

  Future<void> _tryResumeSession() async {
    if (!mounted) return;
    try {
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
      bool groupExists = false;
      try {
        groupExists = await _firebaseService
            .groupExists(savedCode)
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw TimeoutException('Group check timed out'),
            );
      } catch (e) {
        groupExists = false;
      }
      if (!mounted) return;
      if (groupExists) {
        _initTimeout?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                HomeScreen(groupCode: savedCode, userName: savedName),
          ),
        );
      } else {
        await _localStorage.clearSession();
        _navigateToGroupScreen();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'تعذّر تحميل الجلسة. حاول مرة أخرى.';
      });
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(
        info: info,
        updateService: _updateService,
        onDismiss: _tryResumeSession,
      ),
    );
  }

  void _navigateToGroupScreen() {
    if (!mounted) return;
    _initTimeout?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const GroupScreen()),
    );
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });
    _startInit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              widget.accentColor,
              widget.accentColor.withValues(alpha: 0.8),
              widget.accentColor.withValues(alpha: 0.6),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Spacer(flex: 2),
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: const Column(
                    children: [
                      Text(
                        'GlovoMate',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'تشارك موقعك مع أصدقائك في الوقت الحقيقي',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                if (_hasError)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.white70,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: const Text('إعادة المحاولة'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: widget.accentColor,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
