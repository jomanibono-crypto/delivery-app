import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Helper functions for showing modern bottom sheets with the
/// GlovoMate design language (rounded, blurred background, drag handle).
///
/// USAGE:
///   final result = await AppBottomSheet.show`T`(context,
///     title: '...',
///     child: ...,
///   );

class AppBottomSheet {
  AppBottomSheet._();

  /// Show a standard bottom sheet.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    String? subtitle,
    double initialChildSize = 0.5,
    double minChildSize = 0.3,
    double maxChildSize = 0.9,
    bool isDismissible = true,
    bool enableDrag = true,
    Color? backgroundColor,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => _SheetContainer(
        title: title,
        subtitle: subtitle,
        backgroundColor: backgroundColor,
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        child: child,
      ),
    );
  }

  /// Convenience for an action sheet with vertical buttons.
  static Future<T?> showActions<T>(
    BuildContext context, {
    String? title,
    String? subtitle,
    required List<SheetAction> actions,
  }) {
    return show<T>(
      context,
      title: title,
      subtitle: subtitle,
      initialChildSize: (actions.length * 0.07) + 0.22,
      minChildSize: 0.0,
      maxChildSize: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _SheetActionTile(action: actions[i]),
          ],
        ],
      ),
    );
  }
}

class SheetAction {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final bool isDestructive;

  const SheetAction({
    required this.label,
    this.icon,
    this.iconColor,
    this.backgroundColor,
    this.onTap,
    this.isDestructive = false,
  });
}

class _SheetContainer extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final Color? backgroundColor;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  const _SheetContainer({
    required this.child,
    this.title,
    this.subtitle,
    this.backgroundColor,
    required this.initialChildSize,
    required this.minChildSize,
    required this.maxChildSize,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheetTop),
          ),
          boxShadow: AppColors.shadowLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.ink200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (title != null || subtitle != null) ...[
              const SizedBox(height: AppSpacing.lg),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink900,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.ink500,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.lg),
            Flexible(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  mq.viewInsets.bottom + AppSpacing.xl,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetActionTile extends StatelessWidget {
  final SheetAction action;
  const _SheetActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = action.isDestructive
        ? AppColors.danger
        : (action.iconColor ?? AppColors.indigo600);
    return Material(
      color: action.backgroundColor ??
          (action.isDestructive
              ? AppColors.danger.withValues(alpha: 0.08)
              : AppColors.indigo50),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: action.onTap == null
            ? null
            : () {
                Navigator.pop(context);
                action.onTap!();
              },
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              if (action.icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(action.icon, color: color, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: color.withValues(alpha: 0.4),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
