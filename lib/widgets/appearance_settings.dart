import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/theme_service.dart';

class AppearanceSettings extends StatefulWidget {
  final AppSettings appSettings;
  final ThemeService themeService;
  final VoidCallback onChanged;

  const AppearanceSettings({
    super.key,
    required this.appSettings,
    required this.themeService,
    required this.onChanged,
  });

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  @override
  void initState() {
    super.initState();
    widget.appSettings.addListener(_onChanged);
    widget.themeService.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.appSettings.removeListener(_onChanged);
    widget.themeService.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = widget.themeService.accentColor;

    return Column(
      children: [
        _sectionHeader(context, 'اللون الأساسي'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: ThemeService.accentColors.map((color) {
                final isSelected = color.toARGB32() == accentColor.toARGB32();
                return GestureDetector(
                  onTap: () => widget.themeService.setAccentColor(color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                              width: 3,
                            )
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 24)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader(context, 'المظهر'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text('النظام'),
                    icon: Icon(Icons.brightness_auto_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text('فاتح'),
                    icon: Icon(Icons.light_mode_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text('داكن'),
                    icon: Icon(Icons.dark_mode_rounded, size: 18),
                  ),
                ],
                selected: {widget.themeService.themeMode},
                onSelectionChanged: (selected) {
                  widget.themeService.setThemeMode(selected.first);
                },
                showSelectedIcon: false,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader(context, 'التنبيهات الصوتية'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.volume_up_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تفعيل التنبيهات الصوتية',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Switch(
                  value: widget.appSettings.alertVoiceEnabled,
                  onChanged: (value) {
                    widget.appSettings.setAlertVoiceEnabled(value);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader(context, 'معاينة حية'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: theme.colorScheme.onSurface,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'التطبيق',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.search_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'تنبيه جديد',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'هذا مثال على كيفية ظهور التطبيق مع الإعدادات الحالية.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'إشعارات التطبيق',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Switch(value: true, onChanged: null),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: null,
                    child: const Text('حفظ الإعدادات'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
