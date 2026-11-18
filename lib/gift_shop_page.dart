
import 'package:flutter/material.dart';
import 'package:postgrest/postgrest.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';
import 'theme/theme.dart';
import 'service.dart';
import 'widgets/coin_balance_indicator.dart';
import 'widgets/ad_banner_slot.dart';

class GiftShopPage extends StatefulWidget {
  const GiftShopPage({super.key});

  @override
  State<GiftShopPage> createState() => _GiftShopPageState();
}

class _GiftShopPageState extends State<GiftShopPage> {
  bool _isPurchasing = false;
  late Future<List<Map<String, dynamic>>> _giftsFuture;

  @override
  void initState() {
    super.initState();
    _giftsFuture = _loadGifts();
  }

  Future<List<Map<String, dynamic>>> _loadGifts() => Supabase.instance.client
      .from('gifts')
      .select()
      .eq('isActive', true)
      .order('priceCoins', ascending: true);

  Future<double> _loadCoinBalance() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 0;
    final row = await Supabase.instance.client
        .from(kUsersCollection)
        .select('mainCoins')
        .eq('uid', user.id)
        .maybeSingle();
    final value = row?['mainCoins'];
    return value is num ? value.toDouble() : 0;
  }

  Future<void> _purchase(Map<String, dynamic> gift) async {
    final priceValue = gift['priceCoins'];
    final price = priceValue is num ? priceValue.toDouble() : 0.0;
    if (price <= 0) return;

    double balance;
    try {
      balance = await _loadCoinBalance();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't check your coin balance. Please try again."),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final maxQuantity = (balance / price).floor();
    final quantity = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        int qty = maxQuantity > 0 ? 1 : 0;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final total = price * qty;
            final canAffordOne = maxQuantity > 0;
            return AlertDialog(
              title: Text("Buy ${gift['name']}"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("${price.toStringAsFixed(0)} coins each"),
                  const SizedBox(height: 8),
                  Text("Your balance: ${balance.toStringAsFixed(2)} coins"),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: "Decrease quantity",
                        onPressed: qty > 1 ? () => setDialogState(() => qty--) : null,
                      ),
                      Text("$qty", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (qty < maxQuantity)
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          tooltip: "Increase quantity",
                          onPressed: () => setDialogState(() => qty++),
                        ),
                    ],
                  ),
                  Text(
                    canAffordOne
                        ? "Total: ${total.toStringAsFixed(2)} coins"
                        : "Insufficient coins. You need ${price.toStringAsFixed(0)} coins to buy this gift.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: canAffordOne ? null : AppColors.error,
                    ),
                  ),
                  if (canAffordOne && qty == maxQuantity)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text("Maximum quantity available for your balance.", textAlign: TextAlign.center),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: qty > 0 ? () => Navigator.pop(dialogContext, qty) : null,
                  child: const Text("Buy"),
                ),
              ],
            );
          },
        );
      },
    );

    if (quantity == null) return;

    setState(() { _isPurchasing = true; });
    try {
      final latestBalance = await _loadCoinBalance();
      if (quantity * price > latestBalance) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Insufficient coins. Please add more coins.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
      await Supabase.instance.client.rpc('purchase_gift', params: {
        'p_gift_id': gift['id'],
        'p_quantity': quantity,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Bought ${gift['name']} x$quantity! Check your Bag.")),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorText = e is PostgrestException
            ? '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toLowerCase()
            : e.toString().toLowerCase();
        final isInsufficient = errorText.contains('insufficient') ||
            errorText.contains('not enough') ||
            errorText.contains('low balance') ||
            errorText.contains('insufficient_balance');
        final message = isInsufficient
            ? "Insufficient coins. Please add more coins to your wallet."
            : "Couldn't complete the purchase. Please try again.";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() { _isPurchasing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gift Shop"),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: WalletCoinBalance(),
          ),
        ],
      ),
      bottomNavigationBar: const AdBannerSlot(),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _giftsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final gifts = snapshot.data ?? [];
          if (gifts.isEmpty) {
            return const Center(child: Text("No gifts available."));
          }

          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              MediaQuery.of(context).viewPadding.bottom + 36,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: gifts.length,
            itemBuilder: (context, index) {
              final gift = gifts[index];
              return GestureDetector(
                onTap: _isPurchasing ? null : () => _purchase(gift),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Expanded(child: GlobalCachedImage(imageUrl: gift['gifUrl'] ?? '', fit: BoxFit.contain)),
                      const SizedBox(height: 4),
                      Text(gift['name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text("${gift['priceCoins']}", style: const TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
