import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
String _redactSensitive(String value) {
  return value
      .replaceAll(RegExp(r'(authorization|access[_-]?token|refresh[_-]?token|id[_-]?token|password|client_secret)\s*[:=]\s*[^,;\s]+', caseSensitive: false), r'$1=[REDACTED]')
      .replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'), '[JWT REDACTED]')
      .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false), 'Bearer [REDACTED]');
}

String diagnosticErrorMessage(Object error) {
  late final String detail;
  if (error is FirebaseAuthException) {
    detail = '[Firebase Auth] ${error.code}: ${error.message ?? error.plugin}';
  } else if (error is FirebaseException) {
    detail = '[Firebase] ${error.plugin}/${error.code}: ${error.message ?? 'No provider message'}';
  } else if (error is AuthException) {
    detail = '[Supabase Auth] ${error.statusCode ?? 'no status'}: ${error.message}';
  } else if (error is PostgrestException) {
    detail = '[Supabase Database] ${error.code ?? 'no code'}: ${error.message}';
  } else if (error is StorageException) {
    detail = '[Supabase Storage] ${error.statusCode ?? 'no status'}: ${error.message}';
  } else if (error is FunctionException) {
    // Supabase FunctionsHttpError.details contains the actual response body.
    // Prefer it over the generic HTTP reason phrase so validation failures
    // (e.g. invalid email, password, username or referral code) are visible.
    final response = error.details;
    final responseText = response is Map
        ? (response['error'] ?? response['message'] ?? response).toString()
        : response?.toString();
    detail = '[Supabase Edge Function] HTTP ${error.status ?? 'unknown'}: ${responseText?.isNotEmpty == true ? responseText : error.reasonPhrase ?? 'Request failed'}';
  } else if (error is PlatformException) {
    detail = '[Android / Platform] ${error.code}: ${error.message ?? 'Platform operation failed'}';
  } else {
    detail = '[${errorSource(error)}] ${error.toString()}';
  }
  return _redactSensitive(detail);
}

String friendlyErrorMessage(Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  final detail = diagnosticErrorMessage(error);
  final text = detail.toLowerCase();
  if (text.contains('socketexception') || text.contains('failed host lookup') ||
      text.contains('network is unreachable') || text.contains('clientexception')) {
    return '[Network] Internet connection failed. Check your connection and retry.\n$detail';
  }
  if (text.contains('timed out') || text.contains('timeout')) {
    return '[Network] Request timed out. Retry the operation.\n$detail';
  }
  if (text.contains('permission denied') || text.contains('row-level security') ||
      text.contains('rls') || text.contains('42501')) {
    return '[Supabase Database] Permission denied by RLS/policy. Check the user JWT and table policy.\n$detail';
  }
  if (text.contains('too many requests') || text.contains('rate limit')) {
    return '[${errorSource(error)}] Rate limit reached. Wait before retrying.\n$detail';
  }
  if (text.contains('google_sign_in') || text.contains('sign_in_failed') ||
      text.contains('developer_error') || text.contains('10:')) {
    return '[Google Sign-In] OAuth configuration or credential exchange failed. Check package name, SHA-1/SHA-256 and Web Client ID.\n$detail';
  }
  if (error is FirebaseAuthException || error is FirebaseException ||
      error is AuthException || error is PostgrestException ||
      error is StorageException || error is FunctionException ||
      error is PlatformException) return detail;
  return '[${errorSource(error)}] $fallback\n$detail';
}
