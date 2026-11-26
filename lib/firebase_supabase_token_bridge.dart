import 'package:firebase_auth/firebase_auth.dart';

/// Supplies the current Firebase ID token to Supabase Data API, Storage,
/// Realtime, RPC, and Edge Function requests through Supabase's accessToken
/// callback. Firebase users are provisioned with UUID UIDs and the
/// authenticated custom claim before the app establishes its session.
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
