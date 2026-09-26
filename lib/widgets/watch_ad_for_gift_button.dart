// =============================================================================
// PRO EARN — "Watch ad for random gift" button
// -----------------------------------------------------------------------------
// Shared between messaging/chat_gift_sheet.dart and gifts/gift_button.dart's
// _SendGiftSheet (the reels-page "Bag" sheet), so there's exactly one
// implementation instead of two copies drifting apart. The daily cap
// itself lives server-side in claim_random_gift_from_ad/ad_gift_claims
// (see supabase/migrations/2026_chat_redesign.sql) — using the SAME RPC
// from both places is what makes the limit shared between them; this
// widget just displays that shared count and calls the RPC.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';
import '../ad_preloader.dart';

const int kDailyAdGiftCap = 3; // keep in sync with the RPC's v_daily_cap

class WatchAdForGiftButton extends StatefulWidget {
  const WatchAdForGiftButton({super.key});

  @override
  State<WatchAdForGiftButton> createState() => _WatchAdForGiftButtonState();
}

class _WatchAdForGiftButtonState extends State<WatchAdForGiftButton> {
  bool _isBusy = false;
  int? _claimedToday;

  @override
  void initState() {
    super.initState();
    _loadClaimedToday();
  }

  Future<void> _loadClaimedToday() async {
    try {
      final count = await Supabase.instance.client.rpc('get_ad_gift_claims_today');
      if (mounted) setState(() { _claimedToday = (count as num?)?.toInt() ?? 0; });
    } catch (_) {
      if (mounted) setState(() { _claimedToday = 0; });
    }
  }

  bool get _limitReached => (_claimedToday ?? 0) >= kDailyAdGiftCap;

  void _watchAd() {
    if (_limitReached || _isBusy) return;

    final ad = RewardedAdPreloader.takeReadyAd();
    if (ad == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ad not ready yet — try again in a moment.")),
      );
      RewardedAdPreloader.preload();
      return;
    }

    ad.show(onUserEarnedReward: (rewardedAd, reward) async {
      if (mounted) setState(() { _isBusy = true; });
      try {
        final result = await Supabase.instance.client.rpc('claim_random_gift_from_ad');
        final giftName = (result is List && result.isNotEmpty) ? result.first['giftName'] as String? : null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(giftName != null ? "You got a $giftName! Check your Bag." : "Gift claimed! Check your Bag.")),
          );
          setState(() { _claimedToday = (_claimedToday ?? 0) + 1; });
        }
      } catch (e) {
        debugPrint("claim_random_gift_from_ad failed: $e");
        final message = e.toString().contains('DAILY_LIMIT_REACHED')
            ? "You've hit today's limit for this — come back tomorrow!"
            : "Couldn't claim gift: $e";
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.error));
          if (e.toString().contains('DAILY_LIMIT_REACHED')) setState(() { _claimedToday = kDailyAdGiftCap; });
        }
      } finally {
        if (mounted) setState(() { _isBusy = false; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _claimedToday == null ? null : (kDailyAdGiftCap - _claimedToday!).clamp(0, kDailyAdGiftCap);

    return TextButton.icon(
      onPressed: (_isBusy || _limitReached) ? null : _watchAd,
      icon: _isBusy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.play_circle_outline, size: 18),
      label: Text(
        _limitReached
            ? "Daily limit reached"
            : remaining == null
                ? "Watch ad for random gift"
                : "Watch ad for random gift ($remaining left)",
        style: const TextStyle(fontSize: 12),
      ),
      style: TextButton.styleFrom(foregroundColor: _limitReached ? AppColors.textTertiary : AppColors.accent),
    );
  }
}
