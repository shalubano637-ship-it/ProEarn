import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';

class SignupRewardsPopup extends StatefulWidget {
  static const _hiddenDateKey = 'signup_rewards_popup_hidden_date';

  static String _dateKey(DateTime date) {
    return date.year.toString().padLeft(4, '0') +
        '-' +
        date.month.toString().padLeft(2, '0') +
        '-' +
        date.day.toString().padLeft(2, '0');
  }

  static bool _isHiddenForToday() {
    try {
      final saved = Hive.box('app_settings').get(_hiddenDateKey)?.toString();
      return saved == _dateKey(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static Future<void> _hideForToday() async {
    try {
      await Hive.box('app_settings').put(_hiddenDateKey, _dateKey(DateTime.now()));
    } catch (_) {}
  }


  const SignupRewardsPopup({super.key});

  static Future<void> showIfEligible(BuildContext context) async {
    if (_isHiddenForToday()) return;

    try {
      final status = await Supabase.instance.client.rpc('get_signup_reward_status');
      final data = Map<String, dynamic>.from(status as Map);
      if (data['enabled'] != true) return;
    } catch (e) {
      debugPrint('signup reward eligibility check failed: $e');
      return;
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SignupRewardsPopup(),
    );
  }

  static Future<void> show(BuildContext context) => showIfEligible(context);

  @override
  State<SignupRewardsPopup> createState() => _SignupRewardsPopupState();
}

class _SignupRewardsPopupState extends State<SignupRewardsPopup> {
  bool _loading = true;
  bool _claimingDay = false;
  Map<String, dynamic>? _status;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final first = await Supabase.instance.client.rpc('claim_first_login_reward');
      final firstMap = Map<String, dynamic>.from(first as Map);
      if (firstMap['eligible'] == false) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final status = await Supabase.instance.client.rpc('get_signup_reward_status');
      if (!mounted) return;
      setState(() {
        _status = Map<String, dynamic>.from(status as Map);
        _message = firstMap['alreadyClaimed'] == true
            ? null
            : 'Welcome! You received 50 coins + a random High gift.';
        _loading = false;
      });
    } catch (e) {
      debugPrint('signup reward load failed: $e');
      if (mounted) setState(() { _loading = false; _message = 'Rewards are temporarily unavailable.'; });
    }
  }

  Future<void> _claimDay(int day) async {
    if (_claimingDay) return;
    setState(() => _claimingDay = true);
    try {
      final result = await Supabase.instance.client.rpc('claim_signup_daily_reward', params: {'p_day_number': day});
      final data = Map<String, dynamic>.from(result as Map);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Day $day: You got ${data['giftName']}! Check your Bag.')),
        );
      }
      await _load();
    } catch (e) {
      debugPrint('claim_signup_daily_reward failed: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This daily reward is not available yet.'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _claimingDay = false);
    }
  }

  Future<void> _copyReferral(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral code copied.')));
  }

  Future<void> _shareReferral(String code) async {
    await Share.share('Join me on Pro Earn. Use my referral code: $code');
  }

  String _weekdayLabel(int day) {
    final raw = _status?['rewardStartDate']?.toString();
    if (raw == null || raw.isEmpty) return 'Day $day';
    final start = DateTime.tryParse(raw);
    if (start == null) return 'Day $day';
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[(start.weekday - 1 + day - 1) % 7];
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'low': return 'Low Gift';
      case 'medium': return 'Medium Gift';
      default: return 'High Gift';
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = ((_status?['days'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final code = _status?['referralCode']?.toString() ?? '';
    final enabled = _status?['enabled'] != false;

    return AlertDialog(
      title: const Text('Welcome Rewards'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_message != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
                        child: Text(_message!),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (enabled) ...[
                      const Text('7-Day Gift Calendar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      ...days.map((day) {
                        final n = (day['day'] as num).toInt();
                        final tier = day['tier'].toString();
                        final claimed = day['claimed'] == true;
                        final available = day['available'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            SizedBox(width: 82, child: Text(_weekdayLabel(n), style: const TextStyle(fontWeight: FontWeight.bold))),
                            Expanded(child: Text(_tierLabel(tier))),
                            if (claimed) const Icon(Icons.check_circle, color: AppColors.accent)
                            else if (available) SizedBox(height: 34, child: FilledButton(onPressed: _claimingDay ? null : () => _claimDay(n), child: const Text('Claim')))
                            else const Icon(Icons.lock_outline, size: 20),
                          ]),
                        );
                      }),
                    ],
                    if (code.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Your Referral Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
                          child: Text(code, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 18)),
                        )),
                        IconButton(tooltip: 'Copy code', onPressed: () => _copyReferral(code), icon: const Icon(Icons.copy_outlined)),
                        IconButton(tooltip: 'Share code', onPressed: () => _shareReferral(code), icon: const Icon(Icons.share_outlined)),
                      ]),
                      const SizedBox(height: 5),
                      const Text('Invite a new user: you get a High gift and they get a Medium gift.', style: TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Later'),
        ),
        TextButton.icon(
          onPressed: () async {
            await SignupRewardsPopup._hideForToday();
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.notifications_off_outlined, size: 18),
          label: const Text('Turn off for today'),
        ),
      ],
    );
  }
}