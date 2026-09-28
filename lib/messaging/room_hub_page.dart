import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';
import 'room_chat_page.dart';

class RoomHubPage extends StatefulWidget {
  const RoomHubPage({super.key});
  @override
  State<RoomHubPage> createState() => _RoomHubPageState();
}

class _RoomHubPageState extends State<RoomHubPage> {
  Future<List<Map<String, dynamic>>> _rooms(String kind) async {
    final result = await Supabase.instance.client.rpc('list_rooms', params: {'p_kind': kind});
    return (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() {});
  }

  Future<void> _createRoom() async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    bool privateRoom = false;
    bool busy = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Room name', hintText: "Jerry's Room"),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Password / Private'),
                value: privateRoom,
                onChanged: (v) => setDialogState(() => privateRoom = v),
              ),
              if (privateRoom)
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Room password'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy ? null : () async {
                if (nameController.text.trim().isEmpty ||
                    (privateRoom && passwordController.text.isEmpty)) return;
                setDialogState(() => busy = true);
                try {
                  await Supabase.instance.client.rpc('create_room', params: {
                    'p_name': nameController.text.trim(),
                    'p_password': privateRoom ? passwordController.text : null,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (e) {
                  setDialogState(() => busy = false);
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(e.toString().contains('ROOM_ALREADY_EXISTS')
                            ? 'You can create only one Room.'
                            : 'Could not create Room.'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    passwordController.dispose();
    if (created == true) await _refresh();
  }

  Future<void> _enterRoom(Map<String, dynamic> room) async {
    final hasPassword = room['has_password'] == true;
    String password = '';

    if (hasPassword) {
      final entered = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final controller = TextEditingController();
          return AlertDialog(
            title: const Text('Private Room'),
            content: TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Enter')),
            ],
          );
        },
      );
      if (entered == null) return;
      password = entered;
    }

    try {
      final result = await Supabase.instance.client.rpc('enter_room', params: {
        'p_room_id': room['room_id'],
        'p_password': password.isEmpty ? null : password,
      });
      final row = Map<String, dynamic>.from((result as List).first as Map);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomChatPage(
            roomId: row['room_id'] as String,
            roomNumber: (row['room_number'] as num).toInt(),
            roomName: row['room_name'] as String,
            ownerUid: row['owner_uid'] as String,
            hasPassword: row['has_password'] == true,
            memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
          ),
        ),
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('WRONG_PASSWORD') ? 'Wrong password.' : 'Could not enter Room.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _section(String title, String kind, IconData icon) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rooms(kind),
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? [];
        return ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(icon, color: AppColors.accent),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          children: [
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
            else if (rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Text(
                  kind == 'my' ? 'You have not created a Room yet.' : 'No Rooms available.',
                  style: const TextStyle(color: AppColors.textTertiary),
                ),
              )
            else
              ...rooms.map(
                (room) => ListTile(
                  onTap: () => _enterRoom(room),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.surface,
                    child: Icon(
                      room['has_password'] == true ? Icons.lock_outline : Icons.forum_outlined,
                      color: AppColors.accent,
                    ),
                  ),
                  title: Text(room['room_name']?.toString() ?? 'Room'),
                  subtitle: Text('#' + room['room_number'].toString() + '  •  ' + room['owner_name'].toString()),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_outline, size: 18),
                      const SizedBox(width: 4),
                      Text((room['member_count'] ?? 0).toString()),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: [
          IconButton(tooltip: 'Create Room', icon: const Icon(Icons.add_circle_outline), onPressed: _createRoom),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Chat Rooms', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'One Room per user. Public Rooms need no password; Private Rooms require one.',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          _section('My Room', 'my', Icons.home_work_outlined),
          _section('Public Room', 'public', Icons.public),
          _section('Private Room', 'private', Icons.lock_outline),
        ],
      ),
    );
  }
}
