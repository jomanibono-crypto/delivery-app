/// Convert a Unix-epoch timestamp (milliseconds) to a human-readable
/// relative time string in Arabic.
String relativeTime(int timestampMs) {
  if (timestampMs <= 0) return '';

  final now = DateTime.now().millisecondsSinceEpoch;
  final diff = (now - timestampMs) ~/ 1000; // seconds

  if (diff < 0) return 'الآن';
  if (diff < 60) return 'الآن';
  if (diff < 120) return 'منذ دقيقة';
  if (diff < 3600) return 'منذ ${diff ~/ 60} دقيقة';
  if (diff < 7200) return 'منذ ساعة';
  if (diff < 86400) return 'منذ ${diff ~/ 3600} ساعات';
  if (diff < 172800) return 'أمس';
  if (diff < 604800) return 'منذ ${diff ~/ 86400} أيام';

  // Older than a week — show date
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year;
  return '$day/$month/$year';
}

/// Short version — just "now", "5m", "2h", "Yesterday", date.
String relativeTimeShort(int timestampMs) {
  if (timestampMs <= 0) return '';

  final now = DateTime.now().millisecondsSinceEpoch;
  final diff = (now - timestampMs) ~/ 1000;

  if (diff < 0) return 'الآن';
  if (diff < 60) return 'الآن';
  if (diff < 3600) return '${diff ~/ 60}د';
  if (diff < 86400) return '${diff ~/ 3600}س';
  if (diff < 172800) return 'أمس';
  if (diff < 604800) return '${diff ~/ 86400}ي';

  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return '${date.day}/${date.month}';
}
