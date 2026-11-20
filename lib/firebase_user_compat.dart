import 'package:firebase_auth/firebase_auth.dart';

/// Compatibility getter while the UI transitions from Supabase User.id to
/// Firebase User.uid. The underlying Firebase UID remains the UUID subject
/// used by Supabase RLS.
extension FirebaseUserIdCompat on User {
  String get id => uid;
}
