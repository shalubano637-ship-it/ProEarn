import 'package:flutter/material.dart';
import '../ad_free_access.dart';
import '../widgets/native_ad_card.dart';

/// Full-page in-feed native ad between reels.
class AdMobReelItem extends StatelessWidget {
  final VoidCallback onAdClosed;

  const AdMobReelItem({super.key, required this.onAdClosed});

  @override
  Widget build(BuildContext context) {
    if (AdFreeAccess.isActive) return const SizedBox.shrink();
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: NativeAdCard(
            height: 340,
            onFailed: onAdClosed,
          ),
        ),
      ),
    );
  }
}
