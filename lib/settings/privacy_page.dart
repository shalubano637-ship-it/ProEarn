import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  bool _privateAccount = false;
  String _whoCanMessage = 'everyone';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('isPrivateAccount,whoCanMessage')
          .eq('uid', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _privateAccount = row?['isPrivateAccount'] == true;
        _whoCanMessage = (row?['whoCanMessage'] ?? 'everyone').toString();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load privacy settings.')),
        );
      }
    }
  }

  Future<void> _save({bool? privateAccount, String? whoCanMessage}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final nextPrivate = privateAccount ?? _privateAccount;
    final nextWho = whoCanMessage ?? _whoCanMessage;
    setState(() => _saving = true);
    try {
      if (privateAccount != null) {
        await Supabase.instance.client.rpc(
          'set_private_account',
          params: {'p_is_private': nextPrivate},
        );
      }

      if (whoCanMessage != null) {
        await Supabase.instance.client
            .from('users')
            .update({'whoCanMessage': nextWho})
            .eq('uid', uid); 
      }
      if (!mounted) return;
      setState(() {
        _privateAccount = nextPrivate;
        _whoCanMessage = nextWho;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update privacy settings.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _messageOption(String value, String title, String subtitle) {
    final selected = _whoCanMessage == value;
    return SwitchListTile(
      value: selected,
      onChanged: _saving ? null : (enabled) {
        if (enabled) _save(whoCanMessage: value);
      },
      title: Text(title),
      subtitle: Text(subtitle),
      secondary: Icon(
        value == 'everyone'
            ? Icons.public
            : value == 'followers'
                ? Icons.people_outline
                : Icons.block_outlined,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  value: _privateAccount,
                  onChanged: _saving ? null : (value) => _save(privateAccount: value),
                  title: const Text('Private account'),
                  subtitle: const Text(
                    'People who do not follow you cannot see your posts, followers or following. '
                    'Posts created while your account is private stay out of Reels permanently.',
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  title: Text('Who can message you'),
                  subtitle: Text('Choose who can start a direct conversation with you.'),
                ),
                _messageOption(
                  'everyone',
                  'Everyone',
                  'Anyone can message you. Non-followers of a private account go to Message Requests.',
                ),
                _messageOption(
                  'followers',
                  'Your followers',
                  'Only people who follow you can start a conversation.',
                ),
                _messageOption(
                  'no_one',
                  'No one',
                  'Nobody can start a new conversation with you.',
                ),
              ],
            ),
    );
  }
}
