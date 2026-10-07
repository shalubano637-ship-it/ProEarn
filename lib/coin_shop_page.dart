import 'package:flutter/material.dart';
import 'theme/theme.dart';

class CoinShopPage extends StatelessWidget {
  const CoinShopPage({super.key});

  static const _packs = <({int coins, int price, String bonus})>[
    (coins: 50, price: 10, bonus: ''),
    (coins: 250, price: 50, bonus: ''),
    (coins: 500, price: 100, bonus: ''),
    (coins: 1250, price: 250, bonus: ''),
    (coins: 2500, price: 500, bonus: ''),
    (coins: 5000, price: 1000, bonus: ''),
    (coins: 25000, price: 5000, bonus: 'Best Value'),
  ];

  void _notAvailable(BuildContext context, int coins, int price) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Purchase of $coins coins for ₹$price will be available soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Coin Shop')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Buy Coins', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Icon(Icons.monetization_on, color: AppColors.accent, size: 30),
            ],
          ),
          const SizedBox(height: 6),
          Text('Choose a coin pack. Payments will be enabled later.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: [AppColors.accent.withOpacity(.95), AppColors.accent.withOpacity(.65)]),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on, color: Colors.white, size: 42),
                const SizedBox(width: 12),
                Expanded(child: Text('50 Coins for ₹10',
                  style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _packs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.18,
            ),
            itemBuilder: (context, index) {
              final pack = _packs[index];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _notAvailable(context, pack.coins, pack.price),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pack.bonus.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(pack.bonus, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        )
                      else const SizedBox(height: 22),
                      const Spacer(),
                      Row(children: [
                        const Icon(Icons.monetization_on, color: AppColors.accent, size: 22),
                        const SizedBox(width: 6),
                        Text(pack.coins.toString(), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity,
                        child: FilledButton(
                          onPressed: () => _notAvailable(context, pack.coins, pack.price),
                          child: Text('₹${pack.price}'),
                        )),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Text('Purchases are not connected yet. This page is ready for Play Billing / payment integration later.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
