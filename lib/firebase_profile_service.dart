import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firestore profile adapter. Kept separate from app startup until Firestore
/// is provisioned and matching Security Rules are deployed and emulator-tested.
class FirebaseProfileService {
  FirebaseProfileService._();

  static final FirebaseProfileService instance = FirebaseProfileService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDocument(String uid) =>
      _db.collection('users').doc(uid);

  Future<void> ensureProfile({
    required User user,
    String? username,
    String? referralCode,
    required String termsVersion,
  }) async {
    final ref = _userDocument(user.uid);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) return;

      final emailPrefix = user.email?.split('@').first;
      final safeUsername = username?.trim().isNotEmpty == true
          ? username!.trim()
          : (emailPrefix?.isNotEmpty == true
              ? emailPrefix!
              : 'user_${user.uid.substring(0, 6)}');

      transaction.set(ref, {
        'uid': user.uid,
        'email': user.email,
        'userName': safeUsername,
        'bio': 'No Bio Yet',
        'link': 'No Link',
        'profileUrl': '',
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'termsVersion': termsVersion,
        if (referralCode?.trim().isNotEmpty == true)
          'pendingReferralCode': referralCode!.trim().toUpperCase(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<Map<String, dynamic>?> loadProfile(String uid) async {
    final snapshot = await _userDocument(uid).get();
    return snapshot.data();
  }

  Future<bool> hasAcceptedCurrentTerms({
    required String uid,
    required String termsVersion,
  }) async {
    final snapshot = await _userDocument(uid).get();
    final data = snapshot.data();
    return data != null &&
        data['termsAcceptedAt'] != null &&
        data['termsVersion'] == termsVersion;
  }

  Future<void> acceptCurrentTerms({
    required String uid,
    required String termsVersion,
  }) async {
    await _userDocument(uid).update({
      'termsAcceptedAt': FieldValue.serverTimestamp(),
      'termsVersion': termsVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Fails closed: missing profile or a Firestore error is not treated as
  /// proof that the account is allowed. The caller must handle the exception.
  Future<bool> isBanned(String uid) async {
    final snapshot = await _userDocument(uid).get();
    if (!snapshot.exists) {
      throw StateError('Firebase profile is missing; access cannot be verified.');
    }
    return snapshot.data()?['isBanned'] == true;
  }
}
