import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayBillingService {
  PlayBillingService._();
  static final PlayBillingService instance = PlayBillingService._();

  static const coinProducts = <String, int>{
    'coins_100': 100,
    'coins_275': 275,
    'coins_700': 700,
    'coins_1700': 1700,
    'coins_3800': 3800,
    'coins_9200': 9200,
    'coins_100_first': 100, 'coins_275_first': 275,
    'coins_700_first': 700, 'coins_1700_first': 1700,
    'coins_3800_first': 3800, 'coins_9200_first': 9200,
  };
  static const subscriptionProducts = <String>{
    'ad_free_weekly',
    'ad_free_monthly',
  };
  static const productIds = <String>{
    'coins_100',
    'coins_275',
    'coins_700',
    'coins_1700',
    'coins_3800',
    'coins_9200',
    'coins_100_first', 'coins_275_first', 'coins_700_first',
    'coins_1700_first', 'coins_3800_first', 'coins_9200_first',
    'ad_free_weekly',
    'ad_free_monthly',
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  final ValueNotifier<Map<String, ProductDetails>> products =
      ValueNotifier(<String, ProductDetails>{});
  final ValueNotifier<bool> available = ValueNotifier(false);
  final ValueNotifier<bool> loading = ValueNotifier(false);
  final ValueNotifier<bool> firstCoinOfferAvailable = ValueNotifier(false);
  final ValueNotifier<String?> message = ValueNotifier(null);

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  final Set<String> _processingTokens = <String>{};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        message.value = 'Google Play billing error. Please try again.';
        debugPrint('Purchase stream error: $error');
      },
    );
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user != null) unawaited(refreshSubscription());
    });
    await loadProducts();
    await refreshCoinOfferStatus();
    await refreshSubscription();
  }

  Future<void> loadProducts() async {
    loading.value = true;
    try {
      available.value = await _iap.isAvailable();
      if (!available.value) {
        message.value = 'Google Play billing is unavailable on this device.';
        return;
      }
      final response = await _iap.queryProductDetails(productIds);
      if (response.error != null) message.value = response.error!.message;
      products.value = {
        for (final product in response.productDetails) product.id: product,
      };
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('Play products not created or not active: ${response.notFoundIDs}');
      }
    } catch (error) {
      message.value = 'Could not load Google Play products. Please retry.';
      debugPrint('Product query failed: $error');
    } finally {
      loading.value = false;
    }
  }

  Future<void> buy(String productId) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      message.value = 'Please sign in before making a purchase.';
      return;
    }
    if (!available.value) {
      message.value = 'Google Play billing is not available.';
      return;
    }
    final product = products.value[productId];
    if (product == null) {
      message.value = 'This product is not available in Google Play yet.';
      return;
    }
    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      final launched = coinProducts.containsKey(productId)
          ? await _iap.buyConsumable(purchaseParam: purchaseParam, autoConsume: false)
          : await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!launched) message.value = 'Google Play could not start the purchase.';
    } catch (error) {
      message.value = 'Could not start purchase. Please try again.';
      debugPrint('Purchase launch failed: $error');
    }
  }

  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
      await refreshSubscription();
    } catch (error) {
      message.value = 'Could not restore purchases. Please try again.';
      debugPrint('Restore purchases failed: $error');
    }
  }

  Future<void> refreshCoinOfferStatus() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      firstCoinOfferAvailable.value = false;
      return;
    }
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'play-billing', body: {'action': 'coin_offer_status'},
      );
      firstCoinOfferAvailable.value = response.status == 200 &&
          response.data is Map && response.data['eligible'] == true;
      products.value = {...products.value};
    } catch (error) {
      debugPrint('Coin offer status unavailable: $error');
      firstCoinOfferAvailable.value = false;
    }
  }

  Future<void> refreshSubscription() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'play-billing',
        body: {'action': 'refresh_subscription'},
      );
    } catch (error) {
      debugPrint('Subscription refresh skipped: $error');
    }
    await claimDailySubscriptionCoins();
  }

  Future<void> claimDailySubscriptionCoins() async {
    try {
      final result = await Supabase.instance.client.rpc('claim_ad_free_daily_coins');
      final granted = result is Map ? result['coinsGranted'] : null;
      if (granted is num && granted > 0) {
        message.value = 'Your daily 150 subscription coins have been added.';
      }
    } catch (error) {
      debugPrint('Daily subscription coin claim failed: $error');
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        message.value = 'Waiting for Google Play payment confirmation…';
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        message.value = purchase.error?.message ?? 'Purchase failed.';
        if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        message.value = 'Purchase cancelled.';
        if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) continue;

      final token = purchase.verificationData.serverVerificationData;
      if (token.isEmpty) {
        message.value = 'Google Play did not return a purchase token.';
        continue;
      }
      if (!_processingTokens.add(token)) continue;

      try {
        final response = await Supabase.instance.client.functions.invoke(
          'play-billing',
          body: {
            'action': 'verify',
            'productId': purchase.productID,
            'purchaseToken': token,
          },
        );
        final data = response.data;
        if (response.status < 200 || response.status >= 300 ||
            data is! Map || data['success'] != true) {
          final error = data is Map ? data['error'] : null;
          throw StateError(error?.toString() ?? 'Purchase verification failed.');
        }

        // Acknowledge with the Flutter billing plugin first. Consumable coins
        // are then consumed server-side so the same pack can be bought again.
        if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);

        if (coinProducts.containsKey(purchase.productID)) {
          final consume = await Supabase.instance.client.functions.invoke(
            'play-billing',
            body: {
              'action': 'consume',
              'productId': purchase.productID,
              'purchaseToken': token,
            },
          );
          if (consume.status < 200 || consume.status >= 300 ||
              consume.data is! Map || consume.data['success'] != true) {
            message.value = 'Coins added. Google Play is finishing the transaction.';
          } else {
            final coins = coinProducts[purchase.productID] ?? 0;
            message.value = '$coins coins have been added to your wallet.';
            await refreshCoinOfferStatus();
          }
        } else {
          await claimDailySubscriptionCoins();
          message.value = 'Your Ad-Free Pass is active.';
        }
      } catch (error) {
        // Keep any unacknowledged purchase pending so Google Play can redeliver it.
        message.value = 'Payment verification is pending. Please reopen the app.';
        debugPrint('Purchase verification pending: $error');
      } finally {
        _processingTokens.remove(token);
      }
    }
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    await _authSubscription?.cancel();
    products.dispose();
    firstCoinOfferAvailable.dispose();
    available.dispose();
    loading.dispose();
    message.dispose();
  }
}
