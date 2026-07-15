import 'package:flutter/material.dart';
import '../services/daily_stats_service.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = DailyStatsService();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.bar_chart_rounded, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('إحصائيات اليوم'),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Distance card
            _StatCard(
              icon: Icons.route_rounded,
              label: 'المسافة المقطوعة',
              value: stats.distanceFormatted,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            // Time breakdown
            Row(
              children: [
                Expanded(child: _StatCard(
                  icon: Icons.speed_rounded,
                  label: 'قيادة',
                  value: stats.drivingFormatted,
                  color: Colors.orange,
                )),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  icon: Icons.directions_walk_rounded,
                  label: 'حركة',
                  value: stats.movingFormatted,
                  color: Colors.blue,
                )),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatCard(
                  icon: Icons.pause_circle_rounded,
                  label: 'توقف',
                  value: stats.stoppedFormatted,
                  color: Colors.grey,
                )),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  icon: Icons.timer_rounded,
                  label: 'الإجمالي',
                  value: stats.totalFormatted,
                  color: theme.colorScheme.secondary,
                )),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'يتم تحديث الإحصائيات تلقائياً وإعادة تعيينها يومياً في منتصف الليل.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
