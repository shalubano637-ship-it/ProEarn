// =============================================================================
// PRO EARN — Pure utility functions
// -----------------------------------------------------------------------------
// Deliberately dependency-free (no Flutter widgets, no Supabase) so these
// can be unit tested directly — see test/utils_test.dart. Extracted from
// private State-class methods in social_feed.dart (_formatCommentTimestamp)
// and user_profile_features.dart (_formatTime), which had no test coverage
// because a private method on a State class can't be called from a test
// without instantiating the whole widget.
// =============================================================================

/// Formats a timestamp as relative time for comments: "Just now", "5m ago",
/// "3h ago", or a "HH:MM • D/M/YYYY" fallback beyond 24 hours.
///
/// Accepts `dynamic` because Supabase rows hand back timestamps as either a
/// String or a DateTime depending on the column/driver path — this mirrors
/// the original call sites rather than tightening the signature, so
/// swapping this in doesn't require touching every caller's type.
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

/// Formats a DateTime as a 12-hour clock string, e.g. "02:30 PM".
String formatClockTime(DateTime date) {
  int hour = date.hour;
  final String minute = date.minute.toString().padLeft(2, '0');
  final String period = hour >= 12 ? 'PM' : 'AM';

  if (hour > 12) hour -= 12;
  if (hour == 0) hour = 12;

  return "${hour.toString().padLeft(2, '0')}:$minute $period";
}
