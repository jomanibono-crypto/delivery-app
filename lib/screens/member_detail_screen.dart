import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/relative_time.dart';
import '../services/haversine.dart';

/// Dedicated Member Details screen — full design from reference mockup
/// (Screen 7): gradient profile header, stats grid, action buttons.
class MemberDetailScreen extends StatelessWidget {
  final String memberId;
  final Map<String, dynamic> memberData;
  final Map<String, Map<String, dynamic>> allMembers;
  final String currentUserId;
  final void Function(String id) onFollow;
  final VoidCallback? onClose;

  const MemberDetailScreen({
    super.key,
    required this.memberId,
    required this.memberData,
    required this.allMembers,
    required this.currentUserId,
    required this.onFollow,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = memberId == currentUserId;
    final name = memberData['name'] as String? ?? 'عضو';
    final icon = memberData['icon'] as String? ?? '🧑';
    final online = memberData['online'] as bool? ?? false;
    final lat = memberData['lat'] as double? ?? 0.0;
    final lng = memberData['lng'] as double? ?? 0.0;
    final speedMs = memberData['speed'] as double? ?? 0.0;
    final speedKmh = speedMs * 3.6;
    final lastMoved = memberData['last_moved_at'] as int? ?? 0;
    final ts = memberData['timestamp'] as int? ?? 0;
    final battery = memberData['battery'] as int?;

    // Distance from me
    String distanceStr = '—';
    final me = allMembers[currentUserId];
    if (me != null && !isMe) {
      final myLat = me['lat'] as double? ?? 0.0;
      final myLng = me['lng'] as double? ?? 0.0;
      if (myLat != 0.0 && myLng != 0.0 && lat != 0.0 && lng != 0.0) {
        final dist = calculateDistance(myLat, myLng, lat, lng);
        distanceStr = dist < 1000
            ? '${dist.toStringAsFixed(0)}م'
            : '${(dist / 1000).toStringAsFixed(1)}كم';
      }
    }

    // Stop duration
    String stopDuration = '—';
    if (lastMoved > 0 && speedMs < 1) {
      final stoppedSec = (DateTime.now().millisecondsSinceEpoch - lastMoved) ~/ 1000;
      if (stoppedSec < 60) {
        stopDuration = 'الآن';
      } else if (stoppedSec < 3600) {
        stopDuration = '${stoppedSec ~/ 60}د';
      } else if (stoppedSec < 86400) {
        stopDuration = '${stoppedSec ~/ 3600}س';
      } else {
        stopDuration = '${stoppedSec ~/ 86400}ي';
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Hero Profile Header ──
          SliverAppBar(
            pinned: true,
            expandedHeight: 320,
            backgroundColor: AppColors.indigo700,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.indigo800, AppColors.indigo500],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),
                      Hero(
                        tag: 'avatar_$memberId',
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              icon.isNotEmpty ? icon : '🧑',
                              style: const TextStyle(fontSize: 40),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: AppTypography.displaySm.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: online
                                    ? AppColors.mint500
                                    : Colors.white.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              online ? 'متصل الآن' : 'غير متصل',
                              style: AppTypography.labelMd.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Stats Grid ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.speed_rounded,
                          label: 'السرعة',
                          value: speedKmh > 0
                              ? speedKmh.toStringAsFixed(1)
                              : '0',
                          unit: 'كم/س',
                          color: AppColors.indigo500,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.straighten_rounded,
                          label: 'المسافة مني',
                          value: distanceStr,
                          color: AppColors.orange500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.battery_std_rounded,
                          label: 'البطارية',
                          value: battery != null ? '$battery' : '—',
                          unit: battery != null ? '%' : null,
                          color: battery != null && battery < 20
                              ? AppColors.danger
                              : AppColors.success,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.timer_rounded,
                          label: 'آخر نشاط',
                          value: stopDuration,
                          color: AppColors.purple500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Location Card ──
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.ink100),
                      boxShadow: AppColors.shadowSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.indigo50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: AppColors.indigo500,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              'الإحداثيات',
                              style: AppTypography.titleSm,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: AppColors.ink700,
                            letterSpacing: 0.5,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'آخر تحديث: ${relativeTime(ts)}',
                          style: AppTypography.bodySm,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // ── Action Buttons ──
                  if (!isMe) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _PrimaryActionButton(
                            icon: Icons.my_location_rounded,
                            label: 'تتبع',
                            onPressed: () {
                              Navigator.pop(context);
                              onFollow(memberId);
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _SecondaryActionButton(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'رسالة',
                            onPressed: () {
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SecondaryActionButton(
                      icon: Icons.share_location_rounded,
                      label: 'طلب مشاركة موقعي',
                      fullWidth: true,
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxxl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.ink100),
        boxShadow: AppColors.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: AppTypography.labelSm,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.indigo700,
                    height: 1.0,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink500,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.indigo600, AppColors.indigo500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppColors.shadowGlowPrimary,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool fullWidth;
  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.indigo50,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 52,
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.indigo700, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.indigo700,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
