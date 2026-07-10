import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateService updateService;
  final VoidCallback onDismiss;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.updateService,
    required this.onDismiss,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _statusText = 'جاري التحميل...';
      _progress = 0.0;
    });
    try {
      final filePath = await widget.updateService.downloadApk(
        url: widget.info.downloadUrl!,
        expectedHash: widget.info.apkHash,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusText =
                  'جاري التحميل... ${(_progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _statusText = 'جاري تثبيت التحديث...');
      final installed = await widget.updateService.installApk(filePath);
      if (!mounted) return;
      if (installed) {
        Navigator.of(context).pop();
        widget.onDismiss();
      } else {
        setState(() {
          _isDownloading = false;
          _statusText = 'فشل في تثبيت التحديث. جرّب مرة أخرى.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _statusText = 'خطأ في التحميل: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.system_update_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'إصدار جديد v${info.latestVersion ?? ''}',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'الإصدار: v${info.latestVersion ?? '--'}  •  الحجم: ${info.formattedSize}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if ((info.changelog ?? '').isNotEmpty) ...[
              Text(
                'ما الجديد:',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(info.changelog!, style: theme.textTheme.bodyMedium),
              ),
            ],
            const SizedBox(height: 16),
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _statusText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (_statusText.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _statusText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        actions: [
          if (!_isDownloading)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDismiss();
              },
              child: const Text('تذكير لاحقاً'),
            ),
          if (!_isDownloading)
            FilledButton.icon(
              onPressed: _downloadAndInstall,
              icon: const Icon(Icons.download_rounded, size: 20),
              label: const Text('تحميل التحديث'),
            ),
        ],
      ),
    );
  }
}
