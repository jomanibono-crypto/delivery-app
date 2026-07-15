import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant { primary, tonal, danger, ghost, outline }

/// Unified button used across every screen. Variants:
///   * [AppButtonVariant.primary]  — gradient indigo with shadow
///   * [AppButtonVariant.tonal]    — soft indigo background
///   * [AppButtonVariant.danger]   — rose gradient
///   * [AppButtonVariant.outline]  — transparent with border
///   * [AppButtonVariant.ghost]    — text-only
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final AppButtonVariant variant;
  final double height;
  final bool isLoading;
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.variant = AppButtonVariant.primary,
    this.height = AppSpacing.buttonHeight,
    this.isLoading = false,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;
    final radius = BorderRadius.circular(AppRadius.button);

    final children = <Widget>[];
    if (isLoading) {
      children.add(SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: _spinnerColor(),
        ),
      ));
    } else {
      if (leadingIcon != null) {
        children.add(Icon(
          leadingIcon,
          size: 20,
          color: _foreground(),
        ));
        children.add(const SizedBox(width: AppSpacing.sm));
      }
      children.add(Text(
        label,
        style: AppTypography.buttonLg.copyWith(color: _foreground()),
      ));
      if (trailingIcon != null) {
        children.add(const SizedBox(width: AppSpacing.sm));
        children.add(Icon(trailingIcon, size: 20, color: _foreground()));
      }
    }

    final content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );

    switch (variant) {
      case AppButtonVariant.primary:
        return Container(
          width: fullWidth ? double.infinity : null,
          height: height,
          decoration: BoxDecoration(
            gradient: isDisabled
                ? null
                : const LinearGradient(
                    colors: [AppColors.indigo600, AppColors.indigo500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: isDisabled ? AppColors.ink200 : null,
            borderRadius: radius,
            boxShadow: isDisabled ? null : AppColors.shadowGlowPrimary,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: isDisabled ? null : onPressed,
              borderRadius: radius,
              child: Center(child: content),
            ),
          ),
        );
      case AppButtonVariant.tonal:
        return Container(
          width: fullWidth ? double.infinity : null,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.indigo50,
            border: Border.all(color: AppColors.indigo100, width: 1.5),
            borderRadius: radius,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: isDisabled ? null : onPressed,
              borderRadius: radius,
              child: Center(child: content),
            ),
          ),
        );
      case AppButtonVariant.danger:
        return Container(
          width: fullWidth ? double.infinity : null,
          height: height,
          decoration: BoxDecoration(
            gradient: isDisabled
                ? null
                : const LinearGradient(
                    colors: [AppColors.rose500, Color(0xFFC73050)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: isDisabled ? AppColors.ink200 : null,
            borderRadius: radius,
            boxShadow: isDisabled ? null : AppColors.shadowGlowDanger,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: isDisabled ? null : onPressed,
              borderRadius: radius,
              child: Center(child: content),
            ),
          ),
        );
      case AppButtonVariant.outline:
        return Container(
          width: fullWidth ? double.infinity : null,
          height: height,
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(
              color: isDisabled ? AppColors.ink200 : AppColors.ink300,
              width: 1.5,
            ),
            borderRadius: radius,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: isDisabled ? null : onPressed,
              borderRadius: radius,
              child: Center(child: content),
            ),
          ),
        );
      case AppButtonVariant.ghost:
        return Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: isDisabled ? null : onPressed,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: content,
            ),
          ),
        );
    }
  }

  Color _foreground() {
    if (isLoading) return AppColors.indigo700;
    if (onPressed == null) return AppColors.ink300;
    switch (variant) {
      case AppButtonVariant.primary:
        return Colors.white;
      case AppButtonVariant.tonal:
        return AppColors.indigo700;
      case AppButtonVariant.danger:
        return Colors.white;
      case AppButtonVariant.outline:
        return AppColors.ink700;
      case AppButtonVariant.ghost:
        return AppColors.indigo600;
    }
  }

  Color _spinnerColor() {
    if (onPressed == null) return AppColors.ink300;
    switch (variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.danger:
        return Colors.white;
      case AppButtonVariant.tonal:
      case AppButtonVariant.ghost:
        return AppColors.indigo700;
      case AppButtonVariant.outline:
        return AppColors.ink700;
    }
  }
}
