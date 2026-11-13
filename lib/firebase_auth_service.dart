import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Authentication adapter.
///
/// This is intentionally introduced alongside the existing Supabase flow.
/// App screens are not switched to it until profile provisioning, terms,
/// moderation checks, and backend authorization have Firebase replacements.
class FirebaseAuthService {
  FirebaseAuthService._();

  static final FirebaseAuthService instance = FirebaseAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in Firebase user');
    }
    await user.sendEmailVerification();
  }

  Future<void> sendPasswordReset({required String email}) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> signOut() => _auth.signOut();
}
