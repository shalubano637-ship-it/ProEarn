// =============================================================================
// PRO EARN — Gift shop page
// -----------------------------------------------------------------------------
// Browse the gift catalog and purchase gifts with coins (mainCoins).
// Purchased gifts land in the Bag's Owned tab (source='purchased', never
// expires) via the purchase_gift RPC.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/theme.dart';
import 'service.dart';

class GiftShopPage extends StatefulWidget {
  const GiftShopPage({super.key});

  @override
  State<GiftShopPage> createState() => _GiftShopPageState();
}

class _GiftShopPageState extends State<GiftShopPage> {
  bool _isPurchasing = false;

  Future<void> _purchase(Map<String, dynamic> gift) async {
    final quantity = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        int qty = 1;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text("Buy ${gift['name']}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Price: ${gift['priceCoins']} 🪙 each"),
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
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: "Increase quantity",
                      onPressed: () => setDialogState(() => qty++),
                    ),
                  ],
                ),
                Text(
                  "Total: ${((gift['priceCoins'] as num) * qty).toStringAsFixed(2)} 🪙",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, null), child: const Text("Cancel")),
              ElevatedButton(onPressed: () => Navigator.pop(dialogContext, qty), child: const Text("Buy")),
            ],
          ),
        );
      },
    );

    if (quantity == null) return;

    setState(() { _isPurchasing = true; });
    try {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Purchase failed — please try again."), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() { _isPurchasing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gift Shop")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: Supabase.instance.client
            .from('gifts')
            .select()
            .eq('isActive', true)
            .order('priceCoins', ascending: true),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final gifts = snapshot.data ?? [];
          if (gifts.isEmpty) {
            return const Center(child: Text("No gifts available."));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
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
                      Text("${gift['priceCoins']} 🪙", style: const TextStyle(fontSize: 11, color: AppColors.accent)),
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
