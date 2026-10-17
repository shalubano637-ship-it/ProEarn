import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';
import '../service.dart';
import 'chat_page.dart';

class MessageRequestsPage extends StatefulWidget {
  const MessageRequestsPage({super.key});

  @override
  State<MessageRequestsPage> createState() => _MessageRequestsPageState();
}

class _MessageRequestsPageState extends State<MessageRequestsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client.rpc('get_pending_message_requests');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  void _refresh() {
    if (mounted) setState(() => _future = _load());
  }

  Future<void> _accept(Map<String, dynamic> request) async {
    try {
      await Supabase.instance.client.rpc('accept_message_request', params: {
        'p_request_id': request['id'],
      });
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            otherUid: request['senderId'] as String,
            otherUserName: request['senderUserName']?.toString() ?? 'User',
          ),
        ),
      ).then((_) => _refresh());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not accept request.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    try {
      await Supabase.instance.client.rpc('reject_message_request', params: {
        'p_request_id': request['id'],
      });
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reject request.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Message Requests')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load requests.'));
          }
          final requests = snapshot.data ?? [];
          if (requests.isEmpty) {
            return const Center(
              child: Text('No message requests.', style: TextStyle(color: AppColors.textTertiary)),
            );
          }

          return ListView.separated(
            itemCount: requests.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final r = requests[index];
              final name = r['senderUserName']?.toString() ?? 'User';
              final profile = r['senderProfileUrl']?.toString() ?? '';
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: profile.isNotEmpty ? NetworkImage(profile) : null,
                  child: profile.isEmpty ? const Icon(Icons.person) : null,
                ),
                title: Text(name),
                subtitle: const Text('Wants to message you'),
                onTap: () => _accept(r),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Reject',
                      icon: const Icon(Icons.close, color: AppColors.error),
                      onPressed: () => _reject(r),
                    ),
                    IconButton(
                      tooltip: 'Accept',
                      icon: const Icon(Icons.check, color: AppColors.success),
                      onPressed: () => _accept(r),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
