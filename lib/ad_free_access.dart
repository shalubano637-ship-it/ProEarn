import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Cached, server-owned ad-free entitlement for the signed-in account.
class AdFreeAccess {
  AdFreeAccess._();

  static final ValueNotifier<bool> active = ValueNotifier(false);
  static StreamSubscription<AuthState>? _authSubscription;
  static StreamSubscription<List<Map<String, dynamic>>>? _userSubscription;

  static bool get isActive => active.value;

  static Future<void> initialize() async {
    final client = Supabase.instance.client;
    _authSubscription ??= client.auth.onAuthStateChange.listen((state) {
      unawaited(_watchUser(state.session?.user.id));
    });
    await _watchUser(client.auth.currentUser?.id);
  }

  static Future<void> _watchUser(String? uid) async {
    await _userSubscription?.cancel();
    _userSubscription = null;
    if (uid == null) {
      active.value = false;
      return;
    }

    final client = Supabase.instance.client;
    try {
      final row = await client
          .from(kUsersCollection)
          .select('isAdFree,adFreeUntil')
          .eq('uid', uid)
          .maybeSingle();
      _setFromRow(row);
      _userSubscription = client
          .from(kUsersCollection)
          .stream(primaryKey: ['uid'])
          .eq('uid', uid)
          .listen((rows) {
        _setFromRow(rows.isEmpty ? null : rows.first);
      });
    } catch (error) {
      debugPrint('Ad-free entitlement lookup failed: $error');
      active.value = false;
    }
  }

  static void _setFromRow(Map<String, dynamic>? row) {
    final expiryValue = row?['adFreeUntil'];
    final expiry = expiryValue == null
        ? null
        : DateTime.tryParse(expiryValue.toString());
    active.value = row?['isAdFree'] == true &&
        expiry != null &&
        expiry.isAfter(DateTime.now().toUtc());
  }
}
