

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../models.dart';
import '../theme/theme.dart';
import '../ad_unit_ids.dart';

class GetPromptButton extends StatefulWidget {
  final String postId;
  final String ownerId;
  final String prompt;
  final String currentUserId;

  const GetPromptButton({
    super.key,
    required this.postId,
    required this.ownerId,
    required this.prompt,
    required this.currentUserId,
  });

  @override
  State<GetPromptButton> createState() => _GetPromptButtonState();
}
class _GetPromptButtonState extends State<GetPromptButton> {
  Timer? _localUiUpdateTimer;
  String _cooldownRemainingText = "";
  bool _isLocalCooldownActive = false;

  DateTime? _unlockTime;

  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchCooldownOnce();
    _loadRewardedAd(); // Pre-load the ad when widget mounts
  }

  @override
  void dispose() {
    _localUiUpdateTimer?.cancel();
    _rewardedAd?.dispose(); // Clean up memory leak hazards
    super.dispose();
  }

  void _loadRewardedAd() {
    if (_isAdLoading) return;
    setState(() => _isAdLoading = true);

    final adUnitId = AdUnitIds.rewarded;

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          setState(() {
            _rewardedAd = ad;
            _isAdLoading = false;
          });
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('RewardedAd failed to load: $error');
          setState(() => _isAdLoading = false);
          _rewardedAd = null;
        },
      ),
    );
  }

  void _showRewardedAdPipeline(VoidCallback onAdCompleted) {
    if (_rewardedAd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something wrong! Please try again later.")),
      );
      _loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewardedAd(); // Pre-load the next ad
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewardedAd();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        onAdCompleted();
      },
    );
    
    _rewardedAd = null; // Clear current instance reference after triggering show
  }

  Future<void> _fetchCooldownOnce() async {
    if (widget.currentUserId.isEmpty) return;

    final cooldownDoc = await Supabase.instance.client
        .from(kCooldownsCollection)
        .select()
        .eq('postId', widget.postId)
        .eq('userId', widget.currentUserId)
        .maybeSingle();

    if (cooldownDoc != null && cooldownDoc['unlockTime'] != null && mounted) {
      setState(() {
        _unlockTime = DateTime.parse(cooldownDoc['unlockTime'].toString());
      });
    }

    _startLiveCooldownTracker();
  }

  void _startLiveCooldownTracker() {
    _localUiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final unlockTime = _unlockTime;
      if (unlockTime == null || !mounted) return;

      final now = DateTime.now();
      if (unlockTime.isAfter(now)) {
        final diff = unlockTime.difference(now);
        setState(() {
          _isLocalCooldownActive = true;
          _cooldownRemainingText = "${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
        });
      } else if (_isLocalCooldownActive) {
        setState(() {
          _isLocalCooldownActive = false;
          _cooldownRemainingText = "";
        });
      }
    });
  }

  
      void _handleGetPromptPipeline() async {
    if (widget.currentUserId == widget.ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't get your prompt!")),
      );
      return;
    }

    if (widget.currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please login First!")),
      );
      return;
    }

    final snapshot = await Supabase.instance.client
        .from(kCooldownsCollection)
        .select()
        .eq('postId', widget.postId)
        .eq('userId', widget.currentUserId)
        .maybeSingle();

    int currentMultiplier = 1;
    bool isUnderCooldown = false;

    if (snapshot != null) {
      var data = snapshot;
      currentMultiplier = data['multiplier'] ?? 1;
      
      if (data['unlockTime'] != null) {
        DateTime unlockTime = DateTime.parse(data['unlockTime'].toString());
        if (unlockTime.isAfter(DateTime.now())) {
          isUnderCooldown = true;
        }
      }
    }

    if (isUnderCooldown) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cool-down is active! Please $_cooldownRemainingText wait.")),
      );
      return;
    }

    _showRewardedAdPipeline(() async {
      int baseMinutes = 1; 
      int finalMinutesDuration = baseMinutes * currentMultiplier;
      DateTime nextUnlockTarget = DateTime.now().add(Duration(minutes: finalMinutesDuration));

      await Supabase.instance.client.rpc('redeem_get_prompt', params: {
        'p_post_id': widget.postId,
        'p_user_id': widget.currentUserId,
        'p_owner_id': widget.ownerId,
        'p_next_multiplier': currentMultiplier * 2,
        'p_unlock_time': nextUnlockTarget.toIso8601String(),
      });

      if (mounted) {
        setState(() {
          _isLocalCooldownActive = true;
          _unlockTime = nextUnlockTarget;
        });
        _showPromptResultPopup(context, widget.prompt, finalMinutesDuration);
      }
    });
  }

  void _showPromptResultPopup(BuildContext context, String unlockedText, int currentSessionMinutes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          title: const Row(
            children: [
              Icon(Icons.verified, color: AppColors.success),
              SizedBox(width: 8),
              Text("Prompt Unlocked!"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: AppRadius.smRadius,
                ),
                child: Text(
                  "Next cooldown penalty will be multiplied by 2X. (Current: $currentSessionMinutes min Cooldown)",
                  style: const TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 15),
              const Text("AI Configuration Details:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textTertiary)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.smRadius,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    unlockedText,
                    style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("CANCEL", style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: unlockedText));
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Prompt text successfully copied to clipboard!")),
                );
              },
              child: const Text("COPY PROMPT", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: _isAdLoading 
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning))
              : Icon(
                  Icons.lock_open,
                  color: _isLocalCooldownActive ? AppColors.warning : AppColors.textPrimary,
                  size: 28,
                ),
          tooltip: _isLocalCooldownActive
              ? "Get prompt — on cooldown, $_cooldownRemainingText left"
              : "Get prompt (watch an ad)",
          onPressed: _isAdLoading ? null : _handleGetPromptPipeline,
        ),
        Text(
          _isLocalCooldownActive ? _cooldownRemainingText : "Get",
          style: TextStyle(
            color: _isLocalCooldownActive ? AppColors.warning : AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
