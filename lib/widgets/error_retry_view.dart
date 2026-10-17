
import 'package:universal_io/universal_io.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

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
