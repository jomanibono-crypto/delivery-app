import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Modern bottom navigation bar used by every screen instead of
/// the stock NavigationBar. Floating, glassmorphic, with a single
/// active indicator (indigo pill behind the active icon).
class AppBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.pagePaddingTight,
        0,
        AppSpacing.pagePaddingTight,
        AppSpacing.lg,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      height: AppSpacing.bottomNav,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.ink100),
        boxShadow: AppColors.shadowMd,
      ),
      child: Row(
        children: [
          _item(0, Icons.map_outlined, Icons.map_rounded, 'الخريطة'),
          _item(1, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'الدردشة'),
          _item(2, Icons.block_outlined, Icons.block_rounded, 'السوداء'),
          _item(3, Icons.settings_outlined, Icons.settings_rounded, 'الإعدادات'),
        ],
      ),
    );
  }

  Widget _item(int idx, IconData iconOff, IconData iconOn, String label) {
    final active = selectedIndex == idx;
    return Expanded(
      child: InkWell(
        onTap: () => onDestinationSelected(idx),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.all(AppSpacing.xxs),
          decoration: BoxDecoration(
            color: active ? AppColors.indigo50 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? iconOn : iconOff,
                size: 22,
                color: active ? AppColors.indigo600 : AppColors.ink400,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: active ? AppColors.indigo700 : AppColors.ink400,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
