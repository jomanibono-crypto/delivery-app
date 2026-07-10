import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';
import 'group_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

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
    _initApp();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    try {
      await _firebaseService.signInAnonymously();
    } catch (e) {
      if (e is! FirebaseAuthException) rethrow;
    }
    await _checkForUpdate();
    await _tryResumeSession();
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    final updateInfo = await _updateService.checkForUpdate();
    if (!mounted) return;
    if (updateInfo.updateAvailable) {
      _showUpdateDialog(updateInfo);
    }
  }

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
    bool groupExists = false;
    try {
      groupExists = await _firebaseService.groupExists(savedCode);
    } catch (e) {
      groupExists = false;
    }
    if (!mounted) return;
    if (groupExists) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(groupCode: savedCode, userName: savedName),
        ),
      );
    } else {
      await _localStorage.clearSession();
      _navigateToGroupScreen();
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const GroupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF9800), Color(0xFFF57C00), Color(0xFFEF6C00)],
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
