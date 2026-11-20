import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Identifies the subsystem that raised an exception without exposing secrets.
String errorSource(Object error) {
  if (error is FirebaseAuthException) return 'Firebase Auth';
  if (error is FirebaseException) return 'Firebase';
  if (error is AuthException || error is PostgrestException || error is StorageException || error is FunctionException) return 'Supabase';
  if (error is PlatformException) return 'Android / Platform';
  final text = error.toString().toLowerCase();
  if (text.contains('cloudflare') || text.contains('r2')) return 'Cloudflare R2';
  if (text.contains('billing') || text.contains('purchase') || text.contains('in_app_purchase')) return 'Google Play Billing';
  if (text.contains('google_sign_in') || text.contains('google sign-in') || text.contains('google sign in')) return 'Google Sign-In';
  if (text.contains('socketexception') || text.contains('clientexception') || text.contains('timeout')) return 'Network';
  if (text.contains('firebase')) return 'Firebase';
  if (text.contains('supabase') || text.contains('postgrest') || text.contains('row-level security')) return 'Supabase';
  return 'App';
}

/// Provider code and message are retained for diagnosis. Never include request
/// headers, access tokens, passwords, or service credentials in this string.
String diagnosticErrorMessage(Object error) {
  if (error is FirebaseAuthException) return '[Firebase Auth] \${error.code}: \${error.message ?? error.plugin}';
  if (error is FirebaseException) return '[Firebase] \${error.plugin}/\${error.code}: \${error.message ?? 'No provider message'}';
  if (error is AuthException) return '[Supabase Auth] \${error.statusCode ?? 'no status'}: \${error.message}';
  if (error is PostgrestException) return '[Supabase Database] \${error.code ?? 'no code'}: \${error.message}';
  if (error is StorageException) return '[Supabase Storage] \${error.statusCode ?? 'no status'}: \${error.message}';
  if (error is FunctionException) return '[Supabase Edge Function] HTTP \${error.status ?? 'unknown'}: \${error.reasonPhrase ?? error.details ?? 'Request failed'}';
  if (error is PlatformException) return '[Android / Platform] \${error.code}: \${error.message ?? 'Platform operation failed'}';
  return '[\${errorSource(error)}] \${error.toString()}';
}

String friendlyErrorMessage(Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  final detail = diagnosticErrorMessage(error);
  final text = detail.toLowerCase();
  if (text.contains('socketexception') || text.contains('failed host lookup') ||
      text.contains('network is unreachable') || text.contains('clientexception')) {
    return '[Network] Internet connection failed. Check your connection and retry.\\n$detail';
  }
  if (text.contains('timed out') || text.contains('timeout')) {
    return '[Network] Request timed out. Retry the operation.\\n$detail';
  }
  if (text.contains('permission denied') || text.contains('row-level security') ||
      text.contains('rls') || text.contains('42501')) {
    return '[Supabase Database] Permission denied by RLS/policy. Check the user JWT and table policy.\\n$detail';
  }
  if (text.contains('too many requests') || text.contains('rate limit')) {
    return '[\${errorSource(error)}] Rate limit reached. Wait before retrying.\\n$detail';
  }
  if (text.contains('google_sign_in') || text.contains('sign_in_failed') ||
      text.contains('developer_error') || text.contains('10:')) {
    return '[Google Sign-In] OAuth configuration or credential exchange failed. Check package name, SHA-1/SHA-256 and Web Client ID.\\n$detail';
  }
  if (error is FirebaseAuthException || error is FirebaseException ||
      error is AuthException || error is PostgrestException ||
      error is StorageException || error is FunctionException ||
      error is PlatformException) return detail;
  return '[\${errorSource(error)}] $fallback\\n$detail';
}
