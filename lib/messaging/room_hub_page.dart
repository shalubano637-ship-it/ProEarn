import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';
import 'room_chat_page.dart';

class RoomHubPage extends StatefulWidget {
  final bool embedded;
  const RoomHubPage({super.key, this.embedded = false});
  @override
  State<RoomHubPage> createState() => _RoomHubPageState();
}

class _RoomHubPageState extends State<RoomHubPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final Map<String, Future<List<Map<String, dynamic>>>> _futures = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
  Future<List<Map<String, dynamic>>> _rooms(String kind) async {
    if (_futures.containsKey(kind)) return _futures[kind]!;
    final future = Supabase.instance.client.rpc('list_rooms', params: {'p_kind': kind}).then((result) => (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    _futures[kind] = future;
    final result = await future;
    return result;
  }

  Future<void> _refresh() async {
    _futures.clear();
    if (mounted) setState(() {});
  }

  Future<void> _searchRoom() async {
    final controller = TextEditingController();
    bool busy = false;

    final room = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Find Room'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Room ID',
              hintText: 'Enter numeric Room ID',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy ? null : () async {
                final id = int.tryParse(controller.text.trim());
                if (id == null || id <= 0) return;
                setDialogState(() => busy = true);
                try {
                  final result = await Supabase.instance.client.rpc(
                    'search_room_by_number',
                    params: {'p_room_number': id},
                  );
                  final rows = (result as List)
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList();
                  if (rows.isEmpty) {
                    setDialogState(() => busy = false);
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Room not found.')),
                      );
                    }
                    return;
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, rows.first);
                  }
                } catch (_) {
                  setDialogState(() => busy = false);
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Could not search Room.')),
                    );
                  }
                }
              },
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Search'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (room != null && mounted) {
      await _enterRoom(room);
    }
  }

  Future<void> _createRoom() async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    bool privateRoom = false;
    bool busy = false;

    final created = await showDialog<Map<String, dynamic>>(
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
                  final result = await Supabase.instance.client.rpc('create_room', params: {
                    'p_name': nameController.text.trim(),
                    'p_password': privateRoom ? passwordController.text : null,
                  });
                  final row = Map<String, dynamic>.from((result as List).first as Map);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, row);
                } catch (e) {
                  setDialogState(() => busy = false);
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(e.toString().contains('ROOM_ALREADY_EXISTS')
                            ? 'You can create only one Room.'
                            : e.toString().replaceFirst('PostgrestException(message: ', '').split(', code:').first),
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
    if (created != null) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Room created • ID #${created['room_number']}')),
        );
      }
    }
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
            profileUrl: row['profile_url']?.toString() ?? '',
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
                    radius: 25,
                    backgroundColor: AppColors.border,
                    backgroundImage: (room['profile_url']?.toString().isNotEmpty ?? false) ? CachedNetworkImageProvider(room['profile_url'].toString()) : null,
                    child: (room['profile_url']?.toString().isNotEmpty ?? false) ? null : const Icon(Icons.forum_outlined),
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

  Widget _roomList(String kind) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rooms(kind),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Could not load Rooms: ${snapshot.error}'));
        final rooms = snapshot.data ?? [];
        if (rooms.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(kind == 'my' ? 'You have not created a Room yet.' : 'No Rooms available.'),
            if (kind == 'my') ...[
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _createRoom, icon: const Icon(Icons.add), label: const Text('Create Room')),
            ],
          ]));
        }
        return ListView.separated(
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final room = rooms[i];
            final url = room['profile_url']?.toString() ?? '';
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              onTap: () => _enterRoom(room),
              leading: CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.border,
                backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
                child: url.isEmpty ? const Icon(Icons.forum_outlined) : null,
              ),
              title: Text(room['room_name']?.toString() ?? 'Room', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('#${room['room_number']}  •  ${room['owner_name']}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(room['has_password'] == true ? Icons.lock_outline : Icons.public, size: 18),
                const SizedBox(height: 3),
                Text('${room['member_count'] ?? 0}'),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _roomBody() => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.pillRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: List.generate(3, (index) {
            final selected = _tabs.index == index;
            final labels = const ['My Room', 'Public Room', 'Private Room'];
            return Expanded(
              child: GestureDetector(
                onTap: () => _tabs.animateTo(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : AppColors.transparent,
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: selected ? AppColors.textOnAccent : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    ),
    Expanded(child: TabBarView(controller: _tabs, children: [
      _roomList('my'), _roomList('public'), _roomList('private')
    ])),
  ]);

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            const Expanded(child: Text('Rooms', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
            IconButton(onPressed: _searchRoom, icon: const Icon(Icons.search), tooltip: 'Search Room by ID'),
            IconButton(onPressed: _createRoom, icon: const Icon(Icons.add_circle_outline), tooltip: 'Create Room'),
          ]),
        ),
        Expanded(child: _roomBody()),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Rooms'), actions: [
        IconButton(onPressed: _searchRoom, icon: const Icon(Icons.search), tooltip: 'Search Room by ID'),
        IconButton(onPressed: _createRoom, icon: const Icon(Icons.add_circle_outline), tooltip: 'Create Room'),
      ]),
      body: _roomBody(),
    );
  }
}
