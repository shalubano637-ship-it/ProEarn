/// Converts technical exceptions into short, actionable messages for app users.
/// Keep raw exception details in debug logs only; never display backend internals.
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  final message = error.toString().toLowerCase();

  if (message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('clientexception')) {
    return 'You appear to be offline. Check your internet connection and try again.';
  }
  if (message.contains('timed out') || message.contains('timeout')) {
    return 'The request took too long. Please try again.';
  }
  if (message.contains('invalid login credentials') ||
      message.contains('invalid_credentials')) {
    return 'The email or password is incorrect. Check your details and try again.';
  }
  if (message.contains('invalid email') || message.contains('email address is invalid')) {
    return 'Enter a valid email address and try again.';
  }
  if (message.contains('weak password') || message.contains('password should be at least')) {
    return 'Choose a stronger password that meets the password requirements.';
  }
  if (message.contains('email not confirmed')) {
    return 'Please verify your email address before signing in.';
  }
  if (message.contains('already registered') ||
      message.contains('user already exists')) {
    return 'An account with this email already exists. Try signing in instead.';
  }
  if (message.contains('duplicate key') || message.contains('unique constraint')) {
    return 'This information is already in use. Check your details and try again.';
  }
  if (message.contains('foreign key') || message.contains('violates check constraint')) {
    return 'This action could not be completed with the current information. Please refresh and try again.';
  }
  if (message.contains('permission denied') ||
      message.contains('row-level security') ||
      message.contains('rls')) {
    return 'You do not have permission to do that. Check your account access and try again.';
  }
  if (message.contains('file too large') ||
      message.contains('payload too large') ||
      message.contains('413')) {
    return 'This file is too large. Choose a smaller file and try again.';
  }
  if (message.contains('storage') || message.contains('upload')) {
    return 'We could not upload your file. Check your connection and try again.';
  }
  if (message.contains('rate limit') || message.contains('too many requests')) {
    return 'You have tried too many times. Please wait a moment and try again.';
  }
  if (message.contains('cancelled') || message.contains('canceled')) {
    return 'The action was cancelled.';
  }

  return fallback;
}
