import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'play_billing_service.dart';
import 'theme/theme.dart';
import 'widgets/coin_balance_indicator.dart';
import 'widgets/coin_icon.dart';

class CoinShopPage extends StatefulWidget {
  const CoinShopPage({super.key});

  @override
  State<CoinShopPage> createState() => _CoinShopPageState();
}

class _CoinShopPageState extends State<CoinShopPage> {
  final PlayBillingService _billing = PlayBillingService.instance;
  String? _buyingProduct;

  static const _packs = <({String id, int coins, String tag})>[
    (id: 'coins_100', coins: 100, tag: 'FIRST BUY'),
    (id: 'coins_275', coins: 275, tag: ''),
    (id: 'coins_700', coins: 700, tag: 'POPULAR'),
    (id: 'coins_1700', coins: 1700, tag: ''),
    (id: 'coins_3800', coins: 3800, tag: 'BEST VALUE'),
    (id: 'coins_9200', coins: 9200, tag: ''),
  ];

  @override
  void initState() {
    super.initState();
    _billing.message.addListener(_showBillingMessage);
    unawaited(_billing.initialize());
  }

  @override
  void dispose() {
    _billing.message.removeListener(_showBillingMessage);
    super.dispose();
  }

  void _showBillingMessage() {
    if (!mounted) return;
    final value = _billing.message.value;
    if (value == null || value.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
    _billing.message.value = null;
  }

  Future<void> _buy(String id) async {
    setState(() => _buyingProduct = id);
    await _billing.buy(id);
    if (mounted) setState(() => _buyingProduct = null);
  }

  Future<void> _restore() async {
    await _billing.restorePurchases();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase restore check completed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coin Vault', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: WalletCoinBalance(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.accent.withOpacity(.10),
              colors.surface,
              colors.surface,
            ],
            stops: const [0, .28, 1],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF33270B), Color(0xFF171A27), Color(0xFF29213D)],
                ),
                border: Border.all(color: AppColors.accent.withOpacity(.55)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withOpacity(.25),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: const Center(child: CoinIcon(size: 30)),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PROSN VAULT',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'More coins. More value.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: AppColors.accent, size: 21),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Payments are processed securely by Google Play.',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Ad-Free Passes',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Enjoy ProSN without ads and receive 150 coins each day while your pass is active.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (user != null)
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from(kUsersCollection)
                    .stream(primaryKey: ['uid'])
                    .eq('uid', user.id),
                builder: (context, snapshot) {
                  final row = snapshot.data?.isNotEmpty == true
                      ? snapshot.data!.first
                      : null;
                  final active = row?['isAdFree'] == true &&
                      row?['adFreeUntil'] != null &&
                      DateTime.tryParse(row!['adFreeUntil'].toString())
                              ?.isAfter(DateTime.now()) ==
                          true;
                  if (!active) return const SizedBox.shrink();
                  final until = DateTime.parse(row!['adFreeUntil'].toString()).toLocal();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Ad-Free is active until ${until.day}/${until.month}/${until.year}.',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.green),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            _passCard(
              context: context,
              productId: 'ad_free_weekly',
              title: 'Weekly Pass',
              duration: '7 days',
              tag: 'WEEKLY',
            ),
            const SizedBox(height: 12),
            _passCard(
              context: context,
              productId: 'ad_free_monthly',
              title: 'Monthly Pass',
              duration: '1 month',
              tag: 'BEST VALUE',
            ),
            const SizedBox(height: 20),
            Text(
              'Choose your coin pack',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<Map<String, ProductDetails>>(
              valueListenable: _billing.products,
              builder: (context, products, _) {
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _packs.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: .78,
                  ),
                  itemBuilder: (context, index) {
                    final pack = _packs[index];
                    final product = products[pack.id];
                    final highlighted = index == 0 || pack.tag == 'BEST VALUE';
                    return Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: highlighted
                              ? AppColors.accent
                              : colors.outlineVariant.withOpacity(.65),
                          width: highlighted ? 1.6 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (pack.tag.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(.17),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                              ),
                              child: Text(
                                pack.tag,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  letterSpacing: .8,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.accent,
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: 28),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.accent.withOpacity(.16),
                                    ),
                                    child: const Center(child: CoinIcon(size: 27)),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    pack.coins.toString(),
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    'coins',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: highlighted
                                      ? AppColors.accent
                                      : colors.primary,
                                  foregroundColor: highlighted
                                      ? Colors.black
                                      : colors.onPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: product == null || _buyingProduct != null
                                    ? null
                                    : () => _buy(pack.id),
                                child: Text(
                                  product?.price ?? 'Not available',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<String?>(
              valueListenable: _billing.message,
              builder: (context, value, _) {
                if (value == null || value.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(value, style: theme.textTheme.bodySmall),
                );
              },
            ),
            OutlinedButton.icon(
              onPressed: _restore,
              icon: const Icon(Icons.restore),
              label: const Text('Restore purchases'),
            ),
            const SizedBox(height: 10),
            Text(
              'Coin packs are one-time purchases. Ad-Free Passes renew through Google Play until cancelled. Daily subscription coins can be claimed once per day. Manage or cancel subscriptions in Google Play.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passCard({
    required BuildContext context,
    required String productId,
    required String title,
    required String duration,
    required String tag,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Map<String, ProductDetails>>(
      valueListenable: _billing.products,
      builder: (context, products, _) {
        final product = products[productId];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF25213A), Color(0xFF171A27)],
            ),
            border: Border.all(color: AppColors.accent.withOpacity(.75), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(.08),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withOpacity(.16),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.accent,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(duration, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(.17),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _PassBenefit(text: 'Ad-free app experience'),
              const _PassBenefit(text: '150 coins every day'),
              _PassBenefit(text: 'Up to ${duration == '7 days' ? '1,050' : '4,500'} coins during the pass'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  onPressed: product == null || _buyingProduct != null
                      ? null
                      : () => _buy(productId),
                  child: Text(
                    product == null
                        ? 'Not available in Google Play'
                        : 'Get $title • ${product.price}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PassBenefit extends StatelessWidget {
  const _PassBenefit({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
