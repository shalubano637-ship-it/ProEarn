
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_unit_ids.dart';
import '../theme/theme.dart';
import '../service.dart';
import '../chest_timer_service.dart';

const List<String> _chestDurationLabels = ["1 min", "5 min", "10 min", "30 min", "45 min"];

class ChestsPage extends StatefulWidget {
  const ChestsPage({super.key});

  @override
  State<ChestsPage> createState() => _ChestsPageState();
}

class _ChestsPageState extends State<ChestsPage> {
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadRewardedAd();
    if (!chestTimerService.isLoaded) {
      chestTimerService.initialize();
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) { if (mounted) setState(() => _isBannerLoaded = true); },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    )..load();
  }

  void _loadRewardedAd() {
    if (_isAdLoading) return;
    setState(() { _isAdLoading = true; });
    RewardedAd.load(
      adUnitId: AdUnitIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          if (mounted) setState(() { _isAdLoading = false; });
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          if (mounted) setState(() { _isAdLoading = false; });
        },
      ),
    );
  }

  Future<void> _openChest() => _claimChest(isCoin: false);

  Future<void> _openChest() async {
    final service = chestTimerService;
    if (!service.isUnlocked || _isClaiming) return;
    if (_rewardedAd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ad not ready yet — try again in a moment.")),
      );
      _loadRewardedAd();
      return;
    }

    final adToShow = _rewardedAd!;
    _rewardedAd = null;
    final chestIndexBeingClaimed = service.currentChestIndex;

    adToShow.show(onUserEarnedReward: (ad, reward) async {
      if (mounted) setState(() => _isClaiming = true);
      try {
        final result = await Supabase.instance.client.rpc(
          'claim_chest_reward',
          params: {'p_chest_index': chestIndexBeingClaimed},
        );

        if (mounted) {
          final giftName = result['giftName'] as String?;
          final message = giftName != null
              ? "Chest opened! You got a $giftName! Check your Bag."
              : "Chest opened!";
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
          );
        }
        service.advanceToNextChest();
        _loadRewardedAd();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't claim chest — please try again."),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isClaiming = false);
      }
    });
  }

  String _formatTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rewards")),
      body: Column(
        children: [
          if (_isBannerLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          Expanded(
            child: AnimatedBuilder(
              animation: chestTimerService,
              builder: (context, _) {
                if (!chestTimerService.isLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (chestTimerService.loadError != null) {
                  return Center(
                    child: Padding(padding: const EdgeInsets.all(20), child: Text(chestTimerService.loadError!)),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (index) {
                          final isPast = index < chestTimerService.currentChestIndex;
                          final isActive = index == chestTimerService.currentChestIndex;
                          final isFuture = index > chestTimerService.currentChestIndex;
                          final isUnlockedHere = isActive && chestTimerService.isUnlocked;

                          return _ChestSlot(
                            label: "Chest ${index + 1}",
                            durationLabel: _chestDurationLabels[index],
                            isPast: isPast,
                            isActive: isActive,
                            isFuture: isFuture,
                            isUnlocked: isUnlockedHere,
                            timeLabel: isActive ? _formatTime(chestTimerService.remainingSeconds) : null,
                            isClaiming: isActive && _isClaiming,
                            onOpen: isUnlockedHere ? _openChest : null,
                          );
                        }),
                      ),
                      const SizedBox(height: 28),
                      const SizedBox(height: 28),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text("Gift Shop", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 10),
                      const _GiftShopSection(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftShopSection extends StatefulWidget {
  const _GiftShopSection();

  @override
  State<_GiftShopSection> createState() => _GiftShopSectionState();
}

class _GiftShopSectionState extends State<_GiftShopSection> {
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('gifts')
          .select()
          .eq('isActive', true)
          .order('priceCoins', ascending: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final gifts = snapshot.data ?? [];
        if (gifts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text("No gifts available.")),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
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
    );
  }
}

class _ChestSlot extends StatelessWidget {
  final String label;
  final String durationLabel;
  final bool isPast;
  final bool isActive;
  final bool isFuture;
  final bool isUnlocked;
  final String? timeLabel;
  final bool isClaiming;
  final VoidCallback? onOpen;
  final IconData icon;

  const _ChestSlot({
    required this.label,
    required this.durationLabel,
    required this.isPast,
    required this.isActive,
    required this.isFuture,
    required this.isUnlocked,
    required this.timeLabel,
    required this.isClaiming,
    required this.onOpen,
    this.icon = Icons.card_giftcard,
  });

  @override
  Widget build(BuildContext context) {
    final Color chestColor = isPast
        ? AppColors.textDisabled
        : isUnlocked
            ? AppColors.accent
            : isActive
                ? AppColors.textSecondary
                : AppColors.textDisabled;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Icon(
            isPast ? Icons.check_circle : icon,
            size: 48,
            color: chestColor,
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: isFuture ? AppColors.textDisabled : AppColors.textPrimary)),
          Text(durationLabel, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
          const SizedBox(height: 8),
          if (isActive)
            isUnlocked
                ? SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: isClaiming ? null : onOpen,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.textOnAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: isClaiming
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textOnAccent))
                          : const Text("Open", style: TextStyle(fontSize: 12)),
                    ),
                  )
                : Text(timeLabel ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
