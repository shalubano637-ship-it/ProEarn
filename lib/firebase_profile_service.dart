import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase profile adapter. Sensitive account state is returned only by
/// authenticated callable functions; clients never write moderation fields.
class FirebaseProfileService {
  FirebaseProfileService._();

  static final FirebaseProfileService instance = FirebaseProfileService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

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

  /// Reads only the current user's ban and Terms status from a trusted endpoint.
  Future<Map<String, dynamic>> loadAccountState() async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Sign in before loading account state.');
    }
    final result = await _functions.httpsCallable('getMyAccountState').call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<bool> hasAcceptedCurrentTerms({
    required String uid,
    required String termsVersion,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Cannot inspect another account.');
    }
    final state = await loadAccountState();
    return state['termsAccepted'] == true &&
        state['currentTermsVersion'] == termsVersion;
  }

  Future<void> acceptCurrentTerms({
    required String uid,
    required String termsVersion,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Cannot accept terms for another account.');
    }
    final result = await _functions.httpsCallable('acceptCurrentTerms').call({
      'accepted': true,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    if (data['termsVersion'] != termsVersion) {
      throw StateError('Terms version changed. Review the current Terms again.');
    }
  }

  /// Fails closed: callable errors are propagated and cannot be interpreted
  /// as an unbanned account.
  Future<bool> isBanned(String uid) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Cannot check ban status for another account.');
    }
    final state = await loadAccountState();
    if (state['isBanned'] is! bool) {
      throw StateError('Ban status is unavailable; access cannot be verified.');
    }
    return state['isBanned'] as bool;
  }
}
