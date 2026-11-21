import 'package:firebase_auth/firebase_auth.dart';

/// Supplies a Firebase ID token to Supabase when the Firebase identity is
/// available. This helper is intentionally not wired into Supabase.initialize
/// yet: Firebase users must first be provisioned with UUID UIDs that match
/// public.users.uid, and the third-party-auth/RLS integration must be tested.
class FirebaseSupabaseTokenBridge {
  FirebaseSupabaseTokenBridge({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  Future<String?> getAccessToken() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Future<String?> getRequiredAccessToken() async {
    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('A signed-in Firebase user is required.');
    }
    return token;
  }

  String? get currentFirebaseUid => _firebaseAuth.currentUser?.uid;
}
