// =============================================================================
// PRO EARN — Shared error / offline state widget
// -----------------------------------------------------------------------------
// Every FutureBuilder/StreamBuilder error branch across the app used to
// either show nothing or a bare Text("Something went wrong") with no way
// to retry short of leaving and re-entering the screen. This gives every
// screen a consistent, retryable error state, and specifically calls out
// "no internet" (SocketException) instead of a generic error, since
// that's by far the most common real-world cause and the one users can
// actually act on (turn on WiFi/data and tap Retry) as opposed to a
// genuine server-side failure.
//
// No new package dependency was added for connectivity — this classifies
// errors already thrown by the http/Supabase clients (SocketException on
// a lost connection) rather than polling connectivity state, so there's
// nothing new to add to pubspec.yaml/verify against a live pub server.
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// True if [error] looks like "no internet", so callers can show the
/// friendlier offline copy instead of a generic failure message.
bool isOfflineError(Object? error) {
  if (error == null) return false;
  if (error is SocketException) return true;
  final msg = error.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('network is unreachable') ||
      msg.contains('connection refused') ||
      msg.contains('connection closed');
}

/// Drop-in replacement for a bare error Text() in any FutureBuilder /
/// StreamBuilder `builder:` — shows a clear message plus a working Retry
/// button.
///
/// Usage:
/// ```dart
/// if (snapshot.hasError) {
///   return ErrorRetryView(error: snapshot.error, onRetry: () => setState(() {}));
/// }
/// ```
/// `onRetry` is whatever makes this FutureBuilder re-run its `future:` —
/// usually a `setState(() {})` that reassigns the underlying Future field,
/// or a dedicated `_reload()` method if one already exists on the page.
class ErrorRetryView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  final String? offlineMessage;
  final String? genericMessage;

  const ErrorRetryView({
    super.key,
    required this.error,
    required this.onRetry,
    this.offlineMessage,
    this.genericMessage,
  });

  @override
  Widget build(BuildContext context) {
    final offline = isOfflineError(error);
    final icon = offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded;
    final message = offline
        ? (offlineMessage ?? "No internet connection.")
        : (genericMessage ?? "Something went wrong.");

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text("Retry"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accentMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
