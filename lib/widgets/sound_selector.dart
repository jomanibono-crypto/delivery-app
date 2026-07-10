import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';

class SoundSelector extends StatefulWidget {
  final LocalStorageService localStorage;
  const SoundSelector({super.key, required this.localStorage});

  @override
  State<SoundSelector> createState() => _SoundSelectorState();
}

class _SoundSelectorState extends State<SoundSelector> {
  final NotificationService _notifService = NotificationService();
  String _selected = 'default';
  bool _isLoading = true;

  static const _sounds = [
    ('default', 'افتراضي', '🔔'),
    ('chime1', 'نغمة 1', '🎵'),
    ('chime2', 'نغمة 2', '🎶'),
    ('chime3', 'نغمة 3', '🔊'),
    ('silent', 'صامت', '🔇'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await widget.localStorage.getNotifSound();
    if (mounted) {
      setState(() {
        _selected = saved;
        _isLoading = false;
      });
    }
  }

  Future<void> _select(String key) async {
    setState(() => _selected = key);
    await _notifService.changeSound(key);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم اختيار الصوت'),
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'صوت الإشعار',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sounds.map((s) {
                  final key = s.$1;
                  final label = s.$2;
                  final emoji = s.$3;
                  final isSelected = key == _selected;
                  return GestureDetector(
                    onTap: () => _select(key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(
                                color: theme.colorScheme.primary,
                                width: 2,
                              )
                            : Border.all(color: Colors.transparent),
                      ),
                      child: Text(
                        '$emoji $label',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
