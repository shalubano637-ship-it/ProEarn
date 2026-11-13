import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase profile adapter. Profile creation is performed by a trusted
/// callable function; clients never write moderation or private account data.
class FirebaseProfileService {
  FirebaseProfileService._();

  static final FirebaseProfileService instance = FirebaseProfileService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  DocumentReference<Map<String, dynamic>> _userDocument(String uid) =>
      _db.collection('users').doc(uid);

  Future<void> ensureProfile({
    required User user,
    required String username,
    required String termsVersion,
    required bool acceptedTerms,
    String? referralCode,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('The profile user must be the signed-in Firebase user.');
    }

    final callable = _functions.httpsCallable('provisionMyProfile');
    await callable.call({
      'username': username.trim(),
      'termsVersion': termsVersion.trim(),
      'acceptedTerms': acceptedTerms,
      'referralCode': referralCode?.trim() ?? '',
    });
  }

  /// Requires collection-specific read rules to be deployed before use.
  Future<Map<String, dynamic>?> loadProfile(String uid) async {
    final snapshot = await _userDocument(uid).get();
    return snapshot.data();
  }

  /// Requires a trusted profile read endpoint or reviewed read rules.
  Future<bool> hasAcceptedCurrentTerms({
    required String uid,
    required String termsVersion,
  }) async {
    final snapshot = await _db.collection('userPrivate').doc(uid).get();
    final data = snapshot.data();
    return data != null &&
        data['termsAcceptedAt'] != null &&
        data['termsVersion'] == termsVersion;
  }

  /// Terms changes must be recorded through a trusted callable endpoint.
  /// Direct client writes are intentionally not allowed by current rules.
  Future<void> acceptCurrentTerms({
    required String uid,
    required String termsVersion,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Cannot accept terms for another account.');
    }
    throw UnimplementedError(
      'A trusted terms-acceptance callable must be deployed before this operation is enabled.',
    );
  }

  /// A ban check must never fail open. Direct reads require reviewed rules;
  /// errors and missing profiles are intentionally propagated to the caller.
  Future<bool> isBanned(String uid) async {
    final snapshot = await _userDocument(uid).get();
    if (!snapshot.exists) {
      throw StateError('Firebase profile is missing; access cannot be verified.');
    }
    return snapshot.data()?['isBanned'] == true;
  }
}
