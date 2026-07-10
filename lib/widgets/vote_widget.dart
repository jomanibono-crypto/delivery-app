import 'package:flutter/material.dart';
import '../services/alert_service.dart';

class VoteWidget extends StatelessWidget {
  final AlertData alert;
  final String currentUserId;
  final Future<void> Function(String vote) onVote;

  const VoteWidget({
    super.key,
    required this.alert,
    required this.currentUserId,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final myVote = alert.votes[currentUserId];
    final stillThere = alert.voteCountStillThere;
    final gone = alert.voteCountGone;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _voteButton(
              context: context,
              label: '👍 لا يزال موجوداً',
              count: stillThere,
              isSelected: myVote == 'still_there',
              color: Colors.green,
              onTap: () => onVote('still_there'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _voteButton(
              context: context,
              label: '👎 ذهب',
              count: gone,
              isSelected: myVote == 'gone',
              color: Colors.red,
              onTap: () => onVote('gone'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voteButton({
    required BuildContext context,
    required String label,
    required int count,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? color : theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? color
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
