import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'group_screen.dart';
import 'home_screen.dart';

/// GlovoMate splash screen — fully redesigned (v1.9.0+).
///
/// Visual changes vs. v1.8:
///   * Deep indigo gradient (no more flat orange) — see [AppColors.splashGradient]
///   * Glass logo tile with subtle scale animation
///   * Loading dots use staggered pulse
///   * Auto-update flow unchanged but UI matches new design
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

  double _downloadProgress = 0.0;
  bool _isDownloadingUpdate = false;
  bool _downloadComplete = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.3, 0.75, curve: Curves.easeIn),
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
        setState(() => _isDownloadingUpdate = true);
        await _downloadUpdate(updateInfo);
        return;
      }
    } catch (_) {
      // silently skip
    }
  }

  Future<void> _downloadUpdate(UpdateInfo info) async {
    try {
      final filePath = await _updateService.downloadApk(
        url: info.downloadUrl!,
        expectedHash: info.apkHash,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadComplete = true;
        _isDownloadingUpdate = false;
      });
      await _updateService.installApk(filePath);
    } catch (e) {
      debugPrint('[Splash] Auto-update download failed: $e');
      if (mounted) {
        setState(() {
          _isDownloadingUpdate = false;
          _downloadComplete = false;
        });
      }
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
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: Stack(
          children: [
            // Decorative blurred orbs for depth
            const Positioned(
              top: -80,
              right: -80,
              child: _GlowOrb(
                size: 240,
                color: AppColors.indigo300,
                opacity: 0.4,
              ),
            ),
            const Positioned(
              bottom: -100,
              left: -60,
              child: _GlowOrb(
                size: 280,
                color: AppColors.orange500,
                opacity: 0.18,
              ),
            ),
            SafeArea(
              child: _SplashContent(
                scaleAnim: _scaleAnim,
                fadeAnim: _fadeAnim,
                hasError: _hasError,
                errorMessage: _errorMessage,
                isDownloadingUpdate: _isDownloadingUpdate,
                downloadComplete: _downloadComplete,
                downloadProgress: _downloadProgress,
                onRetry: _retry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _GlowOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  final Animation<double> scaleAnim;
  final Animation<double> fadeAnim;
  final bool hasError;
  final String errorMessage;
  final bool isDownloadingUpdate;
  final bool downloadComplete;
  final double downloadProgress;
  final VoidCallback onRetry;

  const _SplashContent({
    required this.scaleAnim,
    required this.fadeAnim,
    required this.hasError,
    required this.errorMessage,
    required this.isDownloadingUpdate,
    required this.downloadComplete,
    required this.downloadProgress,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          // Logo
          ScaleTransition(
            scale: scaleAnim,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_on_rounded,
                size: 56,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          FadeTransition(
            opacity: fadeAnim,
            child: Column(
              children: [
                Text(
                  'GlovoMate',
                  style: AppTypography.displayMd.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'شارك موقعك مع أصدقائك\nفي الوقت الحقيقي',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMd.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 3),
          if (hasError) _ErrorBlock(message: errorMessage, onRetry: onRetry)
          else if (isDownloadingUpdate) _DownloadProgress(progress: downloadProgress)
          else if (downloadComplete) _DownloadComplete()
          else
            const _LoadingDots(),
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            'v1.9.0+42 · Made with ❤️',
            style: AppTypography.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.45),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = ((_c.value - delay) % 1.0);
            final opacity = (1 - (t - 0.5).abs() * 2).clamp(0.2, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  final double progress;
  const _DownloadProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'جاري تحميل التحديث... ${(progress * 100).toStringAsFixed(0)}%',
            style: AppTypography.bodySm.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadComplete extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'تم تحميل التحديث',
          style: AppTypography.bodySm.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(
              color: Colors.white,
              height: 1.55,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _RetryButton(onPressed: onRetry),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _RetryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: AppColors.indigo600,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'إعادة المحاولة',
                style: AppTypography.buttonLg.copyWith(
                  color: AppColors.indigo600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
