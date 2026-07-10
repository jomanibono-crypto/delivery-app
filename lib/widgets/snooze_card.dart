import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';

class SnoozeCard extends StatefulWidget {
  final LocalStorageService localStorage;
  const SnoozeCard({super.key, required this.localStorage});

  @override
  State<SnoozeCard> createState() => _SnoozeCardState();
}

class _SnoozeCardState extends State<SnoozeCard> {
  int _mutedUntil = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final until = await widget.localStorage.getMutedUntil();
    if (mounted) setState(() => _mutedUntil = until);
  }

  Future<void> _snooze(Duration duration) async {
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await widget.localStorage.setMutedUntil(until);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إيقاف الإشعارات لمدة ${_fmtDuration(duration)}'),
          backgroundColor: const Color(0xFF1565C0),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _fmtDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours} ساعة';
    return '${d.inMinutes} دقيقة';
  }

  Future<void> _cancel() async {
    await widget.localStorage.setMutedUntil(null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().millisecondsSinceEpoch;
    final isMuted = _mutedUntil > now;

    final endTime = isMuted
        ? DateTime.fromMillisecondsSinceEpoch(_mutedUntil)
        : null;
    final hh = endTime?.hour.toString().padLeft(2, '0') ?? '--';
    final mm = endTime?.minute.toString().padLeft(2, '0') ?? '--';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إيقاف الإشعارات مؤقتاً',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (isMuted) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.notifications_off_rounded,
                        color: Color(0xFFF57C00),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'متوقفة حتى $hh:$mm',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _cancel,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFF57C00),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _snoozeButton('15 دقيقة', const Duration(minutes: 15)),
                  _snoozeButton('30 دقيقة', const Duration(minutes: 30)),
                  _snoozeButton('1 ساعة', const Duration(hours: 1)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _snoozeButton(String label, Duration duration) {
    return FilledButton.tonal(
      onPressed: () => _snooze(duration),
      child: Text(label),
    );
  }
}
