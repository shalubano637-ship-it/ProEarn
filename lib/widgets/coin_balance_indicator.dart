import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../theme/theme.dart';
import 'coin_icon.dart';

/// Single source and visual style for the user's wallet balance across the app.
class WalletCoinBalance extends StatelessWidget {
  const WalletCoinBalance({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from(kUsersCollection)
          .stream(primaryKey: ['uid'])
          .eq('uid', user.id),
      builder: (context, snapshot) {
        final raw = snapshot.data != null && snapshot.data!.isNotEmpty
            ? snapshot.data!.first['mainCoins']
            : 0;
        final coins = raw is num ? raw.toDouble() : 0.0;
        final colors = Theme.of(context).colorScheme;

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoinIcon(size: 18),
                const SizedBox(width: 4),
                Text(
                  coins.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.add_circle_outline, size: 15, color: colors.onSurface),
              ],
            ),
          ),
        );
      },
    );
  }
}
