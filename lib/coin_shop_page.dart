import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';
import 'theme/theme.dart';
import 'widgets/coin_balance_indicator.dart';
import 'widgets/coin_icon.dart';

class CoinShopPage extends StatelessWidget {
  const CoinShopPage({super.key});

  static const _packs = <({int coins, int bonus, int originalPrice, int offerPrice, String gift, String tag})>[
    (coins: 100, bonus: 0, originalPrice: 29, offerPrice: 9, gift: 'Mini Gift', tag: 'FIRST BUY'),
    (coins: 250, bonus: 25, originalPrice: 49, offerPrice: 19, gift: 'Love Gift', tag: ''),
    (coins: 600, bonus: 100, originalPrice: 99, offerPrice: 39, gift: 'Star Gift', tag: 'POPULAR'),
    (coins: 1400, bonus: 300, originalPrice: 199, offerPrice: 79, gift: 'Super Gift', tag: ''),
    (coins: 3000, bonus: 800, originalPrice: 399, offerPrice: 149, gift: 'Royal Gift', tag: 'BEST VALUE'),
    (coins: 7000, bonus: 2200, originalPrice: 799, offerPrice: 299, gift: 'Mega Gift', tag: ''),
  ];

  void _paymentNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payments are not connected yet. No payment has been taken.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [AppColors.accent.withOpacity(.10), colors.surface, colors.surface],
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
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF33270B), Color(0xFF171A27), Color(0xFF29213D)]),
                border: Border.all(color: AppColors.accent.withOpacity(.55)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 54, height: 54, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent,
                    boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(.25), blurRadius: 18)]),
                    child: const Center(child: CoinIcon(size: 30))),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PRO EARN VAULT', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('More coins. More gifts.', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                  ])),
                ]),
                const SizedBox(height: 18),
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.08), borderRadius: BorderRadius.circular(14)),
                  child: const Row(children: [
                    Icon(Icons.card_giftcard_rounded, color: AppColors.accent, size: 22), SizedBox(width: 9),
                    Expanded(child: Text('Every pack comes with a bonus gift', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                  ])),
                const SizedBox(height: 12),
                const Text('FIRST PURCHASE DEALS: UP TO 70% OFF', style: TextStyle(color: AppColors.accent, fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                const Text('Original prices are crossed out; first-purchase offer prices are shown below.', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 20),
            Text('Ad-Free Passes', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('No ads anywhere in Pro Earn + 150 coins every day while your pass is active.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            _passCard(
              context: context,
              title: 'Weekly Pass',
              duration: '7 days',
              price: '₹99',
              tag: 'WEEKLY',
              benefits: const ['Ad-free app experience', '150 coins every day', 'Up to 1,050 coins over 7 days'],
            ),
            const SizedBox(height: 12),
            _passCard(
              context: context,
              title: 'Monthly Pass',
              duration: '30 days',
              price: '₹299',
              tag: 'BEST VALUE',
              colors: colors,
              theme: theme,
              benefits: const ['Ad-free app experience', '150 coins every day', 'Up to 4,500 coins over 30 days'],
            ),
            const SizedBox(height: 20),
            Text('Choose your coin pack', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _packs.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .78),
              itemBuilder: (context, index) {
                final pack = _packs[index];
                final first = index == 0;
                final highlighted = first || pack.tag == 'BEST VALUE';
                return Container(
                  decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: highlighted ? AppColors.accent : colors.outlineVariant.withOpacity(.65), width: highlighted ? 1.6 : 1),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (pack.tag.isNotEmpty)
                      Container(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        decoration: BoxDecoration(color: AppColors.accent.withOpacity(.17), borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
                        child: Text(pack.tag, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, letterSpacing: .8, fontWeight: FontWeight.w900, color: AppColors.accent)))
                    else const SizedBox(height: 28),
                    Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent.withOpacity(.16)),
                          child: const Center(child: CoinIcon(size: 27))),
                        const SizedBox(height: 7),
                        Text('${pack.coins + pack.bonus}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                        Text('coins total', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                        if (pack.bonus > 0) Padding(padding: const EdgeInsets.only(top: 4),
                          child: Text('+ ${pack.bonus} bonus', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w800))),
                        const SizedBox(height: 7),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.card_giftcard_rounded, color: AppColors.accent, size: 14), const SizedBox(width: 4),
                          Flexible(child: Text(pack.gift, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                        ]),
                      ]))),
                    Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: Column(children: [
                        Text('₹${pack.originalPrice}', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant, decoration: TextDecoration.lineThrough, decorationThickness: 2)),
                        const SizedBox(height: 2),
                        SizedBox(width: double.infinity, child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: highlighted ? AppColors.accent : colors.primary,
                            foregroundColor: highlighted ? Colors.black : colors.onPrimary, padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _paymentNotice(context),
                          child: Text('₹${pack.offerPrice}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        )),
                      ])),
                  ]),
                );
              },
            ),
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: colors.surfaceContainerHighest.withOpacity(.55), borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, color: colors.onSurfaceVariant, size: 18), const SizedBox(width: 8),
                Expanded(child: Text('Pass and coin-pack payments are not connected yet. These prices are display-only; tapping a pass or pack will not charge you, activate ad-free access, or grant coins.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.35))),
              ])),
          ],
        ),
      ),
    );
  }

Widget _passCard({
  required BuildContext context,
  required String title,
  required String duration,
  required String price,
  required String tag,
  required List<String> benefits,
}) {
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
        BoxShadow(color: AppColors.accent.withOpacity(.08), blurRadius: 16, offset: const Offset(0, 5)),
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
              child: const Icon(Icons.workspace_premium_rounded, color: AppColors.accent, size: 25),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(duration, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: AppColors.accent.withOpacity(.17), borderRadius: BorderRadius.circular(20)),
              child: Text(tag, style: const TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...benefits.map((benefit) => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 17),
              const SizedBox(width: 8),
              Expanded(child: Text(benefit, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
            ],
          ),
        )),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pass payments are not connected yet. No payment has been taken.')),
              );
            },
            child: Text('Get $title • $price', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
        ),
      ],
    ),
  );
}

}
