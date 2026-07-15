import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Reusable text input matching the new design language.
class AppInput extends StatelessWidget {
  final String? label;
  final String? hint;
  final String? value;
  final IconData? leadingIcon;
  final String? suffixText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final TextAlign? textAlign;
  final int? maxLength;
  final bool autofocus;
  final String? errorText;
  final bool obscureText;

  const AppInput({
    super.key,
    this.label,
    this.hint,
    this.value,
    this.controller,
    this.focusNode,
    this.leadingIcon,
    this.suffixText,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textDirection,
    this.textAlign,
    this.maxLength,
    this.autofocus = false,
    this.errorText,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: errorText != null
              ? AppColors.danger
              : AppColors.ink200,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.sm,
              ),
              child: Icon(
                leadingIcon,
                size: 22,
                color: AppColors.indigo500,
              ),
            ),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              obscureText: obscureText,
              keyboardType: keyboardType,
              textDirection: textDirection ?? TextDirection.rtl,
              textAlign: textAlign ?? TextAlign.start,
              maxLength: maxLength,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: AppTypography.bodyLg.copyWith(
                color: AppColors.ink900,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                border: InputBorder.none,
                counterText: '',
                labelText: label,
                labelStyle: AppTypography.labelSm.copyWith(
                  color: AppColors.ink400,
                ),
                floatingLabelStyle: AppTypography.labelSm.copyWith(
                  color: AppColors.indigo600,
                ),
                hintText: hint,
                hintStyle: AppTypography.bodyLg.copyWith(
                  color: AppColors.ink300,
                  fontWeight: FontWeight.w500,
                ),
                errorText: errorText,
                errorStyle: AppTypography.caption.copyWith(
                  color: AppColors.danger,
                ),
                suffixText: suffixText,
                suffixStyle: AppTypography.labelMd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
