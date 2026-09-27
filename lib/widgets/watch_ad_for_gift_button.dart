import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';
import '../ad_preloader.dart';

const int kDailyAdGiftCap = 3;
const List<int> kAdGiftChestUnlockMinutes = [1, 3, 5];

class WatchAdForGiftButton extends StatefulWidget {
  const WatchAdForGiftButton({super.key});

  @override
  State<WatchAdForGiftButton> createState() => _WatchAdForGiftButtonState();
}

class _WatchAdForGiftButtonState extends State<WatchAdForGiftButton> {
  bool _isBusy = false;
  int _claimedToday = 0;
  DateTime? _nextUnlockAt;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final result = await Supabase.instance.client.rpc('get_ad_gift_chest_status');
      if (!mounted) return;

      final data = Map<String, dynamic>.from(result as Map);
      final claimed = (data['claimedToday'] as num?)?.toInt() ?? 0;
      final nextUnlockRaw = data['nextUnlockAt']?.toString();

      setState(() {
        _claimedToday = claimed;
        _nextUnlockAt = nextUnlockRaw == null ? null : DateTime.parse(nextUnlockRaw).toLocal();
      });
      _startCountdown();
    } catch (e) {
      debugPrint('get_ad_gift_chest_status failed: $e');
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _updateCountdown();

    if (_nextUnlockAt == null || _claimedToday >= kDailyAdGiftCap) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    if (_nextUnlockAt == null) {
      if (mounted && _remainingSeconds != 0) {
        setState(() => _remainingSeconds = 0);
      }
      return;
    }

    final seconds = _nextUnlockAt!.difference(DateTime.now()).inSeconds;
    final next = seconds > 0 ? seconds : 0;

    if (mounted && _remainingSeconds != next) {
      setState(() => _remainingSeconds = next);
    }

    if (next == 0) _countdownTimer?.cancel();
  }

  bool get _limitReached => _claimedToday >= kDailyAdGiftCap;
  bool get _locked => _remainingSeconds > 0;

  String _formatRemaining() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _claimChest() {
    if (_isBusy || _limitReached || _locked) return;

    final ad = RewardedAdPreloader.takeReadyAd();
    if (ad == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not ready yet — try again in a moment.')),
      );
      RewardedAdPreloader.preload();
      return;
    }

    ad.show(onUserEarnedReward: (rewardedAd, reward) async {
      if (mounted) setState(() => _isBusy = true);

      try {
        final result = await Supabase.instance.client.rpc('claim_random_gift_from_ad');
        final giftName = (result is List && result.isNotEmpty)
            ? result.first['giftName'] as String?
            : null;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                giftName != null
                    ? 'Chest claimed! You got a $giftName. Check your Bag.'
                    : 'Chest claimed! Check your Bag.',
              ),
            ),
          );
        }

        await _loadStatus();
        RewardedAdPreloader.preload();
      } catch (e) {
        debugPrint('claim_random_gift_from_ad failed: $e');
        final message = e.toString().contains('DAILY_LIMIT_REACHED')
            ? "You've claimed all 3 gift chests today."
            : e.toString().contains('CHEST_LOCKED')
                ? 'Your next gift chest is still locked.'
                : "Couldn't claim gift chest — please try again.";

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: AppColors.error),
          );
        }
        await _loadStatus();
      } finally {
        if (mounted) setState(() => _isBusy = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _limitReached
        ? 'Daily limit reached'
        : _isBusy
            ? 'Claiming chest...'
            : _locked
                ? 'Claim chest in ${_formatRemaining()}'
                : 'Claim chest for random gift';

    return TextButton.icon(
      onPressed: (_isBusy || _limitReached || _locked) ? null : _claimChest,
      icon: _isBusy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.card_giftcard, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: (_limitReached || _locked) ? AppColors.textTertiary : AppColors.accent,
      ),
    );
  }
}