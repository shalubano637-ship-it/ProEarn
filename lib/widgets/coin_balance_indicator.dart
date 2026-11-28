import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../theme/theme.dart';
import 'coin_icon.dart';

/// Single source and visual style for the user's wallet balance across the app.
class WalletCoinBalance extends StatefulWidget {
  const WalletCoinBalance({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  State<WalletCoinBalance> createState() => _WalletCoinBalanceState();
}

class _WalletCoinBalanceState extends State<WalletCoinBalance> {
  Stream<List<Map<String, dynamic>>>? _coinStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _coinStream = Supabase.instance.client
          .from(kUsersCollection)
          .stream(primaryKey: ['uid'])
          .eq('uid', user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_coinStream == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _coinStream,
      builder: (context, snapshot) {
        final raw = snapshot.data != null && snapshot.data!.isNotEmpty
            ? snapshot.data!.first['mainCoins']
            : 0;
        final coins = raw is num ? raw.toDouble() : 0.0;
        final colors = Theme.of(context).colorScheme;

        return InkWell(
          onTap: widget.onTap,
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
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(.16),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const CoinIcon(size: 16),
                ),
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
