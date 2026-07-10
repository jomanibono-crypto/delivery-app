import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';

class MuteBanner extends StatefulWidget {
  final LocalStorageService localStorage;
  const MuteBanner({super.key, required this.localStorage});

  @override
  State<MuteBanner> createState() => _MuteBannerState();
}

class _MuteBannerState extends State<MuteBanner> {
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

  Future<void> _cancelMute() async {
    await widget.localStorage.setMutedUntil(null);
    if (mounted) setState(() => _mutedUntil = 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_mutedUntil <= 0) return const SizedBox.shrink();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_mutedUntil <= now) return const SizedBox.shrink();

    final endTime = DateTime.fromMillisecondsSinceEpoch(_mutedUntil);
    final hh = endTime.hour.toString().padLeft(2, '0');
    final mm = endTime.minute.toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              'الإشعارات متوقفة حتى $hh:$mm',
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: Color(0xFFE65100),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _cancelMute,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF57C00),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('إلغاء', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
