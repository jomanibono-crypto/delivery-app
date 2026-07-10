import 'package:flutter/material.dart';
import '../services/permission_service.dart';

class SystemAlertCard extends StatefulWidget {
  final bool granted;
  final PermissionService permissionService;
  final ValueChanged<bool> onChanged;

  const SystemAlertCard({
    super.key,
    required this.granted,
    required this.permissionService,
    required this.onChanged,
  });

  @override
  State<SystemAlertCard> createState() => _SystemAlertCardState();
}

class _SystemAlertCardState extends State<SystemAlertCard> {
  bool _isLoading = false;

  Future<void> _request() async {
    setState(() => _isLoading = true);
    final granted = await widget.permissionService.requestSystemAlertWindow(
      context,
    );
    widget.onChanged(granted);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final granted = widget.granted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: granted
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    granted
                        ? Icons.check_circle_rounded
                        : Icons.layers_outlined,
                    size: 20,
                    color: granted
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'الظهور فوق التطبيقات الأخرى',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: granted
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    granted ? 'مفعل' : 'غير مفعل',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: granted
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              granted
                  ? 'الإشعارات المنبثقة ستعمل فوق أي تطبيق'
                  : 'لظهور إشعارات "صاحبك قريب" فوق التطبيقات الأخرى (يوتيوب، واتساب...)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _request,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        granted
                            ? Icons.check_circle_rounded
                            : Icons.layers_outlined,
                        size: 20,
                        color: granted ? theme.colorScheme.tertiary : null,
                      ),
                label: Text(
                  granted
                      ? 'تم منح الصلاحية'
                      : 'طلب صلاحية الظهور فوق التطبيقات',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: granted ? theme.colorScheme.tertiary : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(
                    color: granted
                        ? theme.colorScheme.tertiary.withValues(alpha: 0.5)
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
