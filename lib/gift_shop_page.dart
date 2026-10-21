
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
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [const _CoinMark(size: 18), const SizedBox(width: 5), Text("${gift['priceCoins']} each")]),
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
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [const _CoinMark(size: 18), const SizedBox(width: 5), Text("Total: ${((gift['priceCoins'] as num) * qty).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold))]),
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
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const _CoinMark(size: 18),
                        const SizedBox(width: 4),
                        Text("${gift['priceCoins']}", style: const TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w800)),
                      ]),
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

class _CoinMark extends StatelessWidget {
  final double size;
  const _CoinMark({required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _CoinMarkPainter()),
  );
}

class _CoinMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .46;
    final gold = Paint()..color = const Color(0xFFFFD54F)..isAntiAlias = true;
    final rim = Paint()..color = const Color(0xFFB8860B)..style = PaintingStyle.stroke..strokeWidth = size.width * .07..isAntiAlias = true;
    final inner = Paint()..color = const Color(0xFFFFE082)..style = PaintingStyle.stroke..strokeWidth = size.width * .045..isAntiAlias = true;
    canvas.drawCircle(center, radius, gold);
    canvas.drawCircle(center, radius * .86, rim);
    canvas.drawCircle(center, radius * .70, inner);
    final detail = Paint()..color = const Color(0xFF8A6500)..strokeWidth = size.width * .07..strokeCap = StrokeCap.round..isAntiAlias = true;
    final path = Path()
      ..moveTo(size.width * .32, size.height * .35)
      ..lineTo(size.width * .68, size.height * .35)
      ..moveTo(size.width * .32, size.height * .50)
      ..lineTo(size.width * .62, size.height * .50)
      ..moveTo(size.width * .32, size.height * .65)
      ..lineTo(size.width * .55, size.height * .65);
    canvas.drawPath(path, detail);
  }

  @override
  bool shouldRepaint(covariant _CoinMarkPainter oldDelegate) => false;
}
