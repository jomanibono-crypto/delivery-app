import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/alert_service.dart';

class ProximityAlertSettings extends StatefulWidget {
  final AppSettings appSettings;

  const ProximityAlertSettings({super.key, required this.appSettings});

  @override
  State<ProximityAlertSettings> createState() => _ProximityAlertSettingsState();
}

class _ProximityAlertSettingsState extends State<ProximityAlertSettings> {
  @override
  void initState() {
    super.initState();
    widget.appSettings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.appSettings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.appSettings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'التنبيه عند الاقتراب من النقاط',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // ── Distance Slider ──
            Row(
              children: [
                Text(
                  'مسافة التنبيه',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${settings.alertDistance} متر',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Slider(
              value: settings.alertDistance.toDouble(),
              min: 50,
              max: 500,
              divisions: 5,
              label: '${settings.alertDistance} متر',
              onChanged: (v) => settings.setAlertDistance(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: AppSettings.alertDistanceOptions.map((d) {
                return Text('$d', style: theme.textTheme.labelSmall);
              }).toList(),
            ),
            const Divider(height: 24),

            // ── Alert Type Toggles ──
            Text(
              'أنواع التنبيهات',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...AlertType.values.where((t) => t.isAlert).map((type) {
              final enabled = settings.isAlertTypeEnabled(type.key);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => settings.setAlertTypeEnabled(type.key, !enabled),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: type.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: FittedBox(
                              child: Text(
                                type.label.isNotEmpty
                                    ? type.label.runes.isNotEmpty
                                          ? String.fromCharCode(
                                              type.label.runes.first,
                                            )
                                          : ''
                                    : '',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            type.label,
                            style: TextStyle(
                              fontWeight: enabled
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: enabled,
                          onChanged: (v) =>
                              settings.setAlertTypeEnabled(type.key, v),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const Divider(height: 24),

            // ── Notification / Vibration / Sound Toggles ──
            Text(
              'طريقة التنبيه',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildToggle(
              theme,
              Icons.notifications_rounded,
              'إشعار',
              settings.alertNotificationEnabled,
              (v) => settings.setAlertNotificationEnabled(v),
            ),
            _buildToggle(
              theme,
              Icons.vibration_rounded,
              'اهتزاز',
              settings.alertVibrationEnabled,
              (v) => settings.setAlertVibrationEnabled(v),
            ),
            _buildToggle(
              theme,
              Icons.volume_up_rounded,
              'صوت',
              settings.alertSoundEnabled,
              (v) => settings.setAlertSoundEnabled(v),
            ),
            _buildToggle(
              theme,
              Icons.record_voice_over_rounded,
              'تنبيه صوتي',
              settings.alertVoiceEnabled,
              (v) => settings.setAlertVoiceEnabled(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(
    ThemeData theme,
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
