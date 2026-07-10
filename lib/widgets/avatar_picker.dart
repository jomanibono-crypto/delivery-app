import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';
import '../services/firebase_service.dart';

class AvatarPicker extends StatefulWidget {
  final LocalStorageService localStorage;
  final FirebaseService firebaseService;
  final String groupCode;

  const AvatarPicker({
    super.key,
    required this.localStorage,
    required this.firebaseService,
    required this.groupCode,
  });

  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  String _selected = '🧑';

  static const List<String> _emojiOptions = [
    '🧑',
    '🚗',
    '🏍️',
    '🚲',
    '🚶',
    '📦',
    '🏃',
    '🛵',
    '🚕',
    '🚚',
    '🏠',
    '🎯',
    '⭐',
    '🔵',
    '🔴',
  ];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await widget.localStorage.getUserIcon();
    if (mounted && saved != null) setState(() => _selected = saved);
  }

  Future<void> _select(String emoji) async {
    setState(() => _selected = emoji);
    await widget.localStorage.saveUserIcon(emoji);
    await widget.firebaseService.updateUserIcon(
      groupCode: widget.groupCode,
      icon: emoji,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم اختيار: $emoji'),
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
              'اختر أيقونة تمثلك في المجموعة',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _emojiOptions.map((emoji) {
                final isSelected = emoji == _selected;
                return GestureDetector(
                  onTap: () => _select(emoji),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: isSelected
                          ? Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'الحالي: $_selected',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
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
