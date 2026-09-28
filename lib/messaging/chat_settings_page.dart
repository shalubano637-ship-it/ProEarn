
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import '../theme/theme.dart';
import '../service.dart';
import '../user_profile_features.dart';

class ChatSettingsPage extends StatefulWidget {
  final String otherUid;
  final String otherUserName;

  const ChatSettingsPage({super.key, required this.otherUid, required this.otherUserName});

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  bool? _muted; // null while loading
  bool _isBusy = false;

  bool _isReportOn = false;
  bool _isBlockOn = false;
  String? _selectedReason;

  static const List<String> _reportReasons = [
    "Spam or Misleading",
    "Hate Speech or Violence",
    "Harassment or Bullying",
    "Nudity or Sexual Content",
          "Child Safety / CSAE",
    "Intellectual Property Violation",
  ];

  @override
  void initState() {
    super.initState();
    _loadMuteState();
  }

  Future<void> _loadMuteState() async {
    try {
      final myUid = Supabase.instance.client.auth.currentUser?.id;
      if (myUid == null) return;
      final row = await Supabase.instance.client
          .from(kUsersCollection)
          .select('mutedUsers')
          .eq('uid', myUid)
          .maybeSingle();
      final muted = (row?['mutedUsers'] as List?)?.cast<String>() ?? [];
      if (mounted) setState(() { _muted = muted.contains(widget.otherUid); });
    } catch (_) {
      if (mounted) setState(() { _muted = false; });
    }
  }

  Future<void> _toggleMute(bool value) async {
    setState(() { _muted = value; }); // optimistic
    try {
      await Supabase.instance.client.rpc('toggle_mute_user', params: {
        'p_target_uid': widget.otherUid,
        'p_muted': value,
      });
    } catch (e) {
      if (mounted) {
        setState(() { _muted = !value; }); // revert
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update — please try again."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _confirmAction() async {
    if (!_isReportOn && !_isBlockOn) return;
    if (_isReportOn && _selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a reason!"), backgroundColor: AppColors.error),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isBlockOn ? "Block ${widget.otherUserName}?" : "Report ${widget.otherUserName}?"),
        content: Text(_isBlockOn
            ? "They won't be able to message you or see your posts anymore."
            : "We'll review your report against ${widget.otherUserName}."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Confirm", style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() { _isBusy = true; });
    try {
      if (_isReportOn) {
        await Supabase.instance.client.from(kReportsCollection).insert({
          'reportedBy': Supabase.instance.client.auth.currentUser!.id,
          'reportedUserId': widget.otherUid,
          'reason': _selectedReason,
          'source': 'chat_settings',
        });
      }
      if (_isBlockOn) {
        await Supabase.instance.client.rpc('block_user_and_hide_post', params: {
          'p_blocker_id': Supabase.instance.client.auth.currentUser!.id,
          'p_target_owner_id': widget.otherUid,
          'p_target_post_id': '',
        });
      }

      if (!mounted) return;
      Navigator.pop(context, _isBlockOn ? 'blocked' : 'reported');
    } catch (e) {
      if (mounted) {
        setState(() { _isBusy = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't complete this action — please try again."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _deleteChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text('This removes the chat from your Messages list. The other person keeps their copy.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final conversationId = await Supabase.instance.client.rpc(
        'get_or_create_conversation',
        params: {'p_other_uid': widget.otherUid},
      );
      await Supabase.instance.client.rpc(
        'hide_conversation_for_me',
        params: {'p_conversation_id': conversationId},
      );
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete chat."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Chat Settings"), backgroundColor: AppColors.background),
      body: AbsorbPointer(
        absorbing: _isBusy,
        child: ListView(
          children: [
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<Map<String, dynamic>?>(
              future: Supabase.instance.client.from('public_profiles').select().eq('uid', widget.otherUid).maybeSingle(),
              builder: (context, snapshot) {
                final profileUrl = snapshot.data?['profileUrl'] ?? '';
                final userName = snapshot.data?['userName'] ?? widget.otherUserName;
                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ProfilePage(isOwnProfile: false, otherUser: widget.otherUid)),
                      ),
                      child: ClipOval(
                        child: GlobalCachedImage(imageUrl: profileUrl, width: 88, height: 88, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text("@$userName", style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary)),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            SwitchListTile(
              title: const Text("Mute notifications"),
              subtitle: Text("Turn off push notifications from ${widget.otherUserName}"),
              value: _muted ?? false,
              onChanged: _muted == null ? null : _toggleMute,
              activeColor: AppColors.accent,
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text("Report", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
              subtitle: const Text("Report this user to Pro Earn"),
              secondary: const Icon(Icons.flag_outlined, color: AppColors.error),
              value: _isReportOn,
              onChanged: (v) {
                setState(() {
                  _isReportOn = v;
                  if (v) _isBlockOn = true; // Report always blocks too.
                });
              },
              activeColor: AppColors.error,
            ),
            if (_isReportOn)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: DropdownButtonFormField<String>(
                  value: _selectedReason,
                  hint: const Text("Select a reason"),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: AppRadius.smRadius, borderSide: BorderSide.none),
                  ),
                  items: _reportReasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 14)))).toList(),
                  onChanged: (v) => setState(() { _selectedReason = v; }),
                ),
              ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text("Block", style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
              subtitle: Text(_isReportOn
                  ? "Mandatory while reporting"
                  : "They won't be able to message you or see your posts"),
              secondary: const Icon(Icons.block, color: AppColors.warning),
              value: _isBlockOn,
              onChanged: (v) {
                if (!v && _isReportOn) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Block ko off karne ke liye pehle Report off karo.")),
                  );
                  return;
                }
                setState(() { _isBlockOn = v; });
              },
              activeColor: AppColors.warning,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(
                'Delete chat',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Remove this chat from your Messages list'),
              onTap: _isBusy ? null : _deleteChat,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_isReportOn || _isBlockOn) ? AppColors.error : AppColors.textTertiary,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                  ),
                  onPressed: (_isReportOn || _isBlockOn) ? _confirmAction : null,
                  child: const Text("CONFIRM", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
