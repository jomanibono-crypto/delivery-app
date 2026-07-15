import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import 'home_screen.dart';

/// Create or join a group screen — fully redesigned.
///
/// v1.9.0+ visual changes:
///   * Decorative gradient hero replaces the old orange gradient
///   * Inputs use [AppInput] with focused state + indigo ring
///   * Buttons use [AppButton] variants (primary / tonal)
///   * Footer legal text added in muted style
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final LocalStorageService _localStorage = LocalStorageService();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  final _codeFocus = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'أدخل اسمك أولاً');
      _nameFocus.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final code = await _firebaseService.createGroup();
      _codeController.text = code;

      final userName = _nameController.text.trim();
      await _localStorage.saveSession(userName: userName, groupCode: code);

      await _firebaseService.createPresenceNode(
        groupCode: code,
        name: userName,
      );

      await Clipboard.setData(ClipboardData(text: code));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(groupCode: code, userName: userName),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[CreateGroup] ERROR: ${e.toString()}');
      debugPrint('[CreateGroup] STACK TRACE:\n$st');
      final msg = 'فشل في إنشاء المجموعة: ${e.toString()}';
      setState(() => _errorMessage = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinGroup() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();

    if (code.length != 6) {
      setState(() => _errorMessage = 'الكود يجب أن يكون 6 أرقام');
      _codeFocus.requestFocus();
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'أدخل اسمك');
      _nameFocus.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final exists = await _firebaseService.groupExists(code);
      if (!exists) {
        setState(() => _errorMessage = 'هذا الكود غير موجود');
        return;
      }

      await _localStorage.saveSession(userName: name, groupCode: code);

      await _firebaseService.createPresenceNode(groupCode: code, name: name);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(groupCode: code, userName: name),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[JoinGroup] ERROR: ${e.toString()}');
      debugPrint('[JoinGroup] STACK TRACE:\n$st');
      final msg = 'فشل في الانضمام: ${e.toString()}';
      setState(() => _errorMessage = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.huge,
            AppSpacing.xxl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeroPanel(),
              const SizedBox(height: AppSpacing.huge),
              Text(
                'ابدأ المغامرة',
                style: AppTypography.displaySm,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'شارك موقعك مع فريقك بكل سهولة',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.ink500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.huge),
              AppInput(
                controller: _nameController,
                focusNode: _nameFocus,
                label: 'اسمك',
                leadingIcon: Icons.person_outline_rounded,
                hint: 'مثال: يوسف',
                keyboardType: TextInputType.name,
                onSubmitted: (_) => _codeFocus.requestFocus(),
              ),
              const SizedBox(height: AppSpacing.md),
              AppInput(
                controller: _codeController,
                focusNode: _codeFocus,
                label: 'كود المجموعة',
                leadingIcon: Icons.vpn_key_outlined,
                hint: '6 أرقام',
                suffixText: 'رقم',
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                maxLength: 6,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                _ErrorBanner(message: _errorMessage!),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'إنشاء مجموعة جديدة',
                leadingIcon: Icons.add_circle_outline_rounded,
                onPressed: _isLoading ? null : _createGroup,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'الانضمام لمجموعة',
                leadingIcon: Icons.login_rounded,
                variant: AppButtonVariant.tonal,
                onPressed: _isLoading ? null : _joinGroup,
              ),
              const SizedBox(height: AppSpacing.huge),
              Text(
                'بإنشائك مجموعة، أنت توافق على شروط الاستخدام وسياسة الخصوصية',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: AppColors.ink400,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppColors.shadowGlowPrimary,
      ),
      child: Stack(
        children: [
          // Decorative rings
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.group_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'مرحباً يا أصدقاء 👋',
                  style: AppTypography.titleLg.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'أنشئ أو انضم لمجموعة',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
