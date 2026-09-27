
String formatRelativeTimestamp(dynamic timestamp) {
  if (timestamp == null) return "Just now";

  final DateTime dateTime = DateTime.parse(timestamp.toString());
  final DateTime now = DateTime.now();
  final Duration difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return "Just now";
  } else if (difference.inMinutes < 60) {
    return "${difference.inMinutes}m ago";
  } else if (difference.inHours < 24) {
    return "${difference.inHours}h ago";
  } else {
    final String timeStr =
        "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    final String dateStr = "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    return "$timeStr • $dateStr";
  }
}

String formatClockTime(DateTime date) {
  int hour = date.hour;
  final String minute = date.minute.toString().padLeft(2, '0');
  final String period = hour >= 12 ? 'PM' : 'AM';

  if (hour > 12) hour -= 12;
  if (hour == 0) hour = 12;

  return "${hour.toString().padLeft(2, '0')}:$minute $period";
}
