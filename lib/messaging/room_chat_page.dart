import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';
import '../cloudflare_media_service.dart';
import '../user_profile_features.dart';

class RoomChatPage extends StatefulWidget {
  final String roomId;
  final int roomNumber;
  final String roomName;
  final String ownerUid;
  final String profileUrl;
  final bool hasPassword;
  final int memberCount;

  const RoomChatPage({
    super.key,
    required this.roomId,
    required this.roomNumber,
    required this.roomName,
    required this.ownerUid,
    this.profileUrl = '',
    required this.hasPassword,
    required this.memberCount,
  });

  @override
  State<RoomChatPage> createState() => _RoomChatPageState();
}

class _RoomChatPageState extends State<RoomChatPage> {
  final _controller = TextEditingController();
  Timer? _timer;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  late String _roomName;
  late bool _hasPassword;
  late int _memberCount;

  String get _myUid => Supabase.instance.client.auth.currentUser?.id ?? '';
  bool get _isOwner => _myUid == widget.ownerUid;

  @override
  void initState() {
    super.initState();
    _roomName = widget.roomName;
    _hasPassword = widget.hasPassword;
    _memberCount = widget.memberCount;
    _loadMessages();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages(silent: true));
  }

  Future<void> _loadMessages({bool silent = false}) async {
    try {
      final result = await Supabase.instance.client.rpc('get_room_messages', params: {
        'p_room_id': widget.roomId,
        'p_limit': 200,
      });
      final rows = (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() { _messages = rows; _loading = false; });
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load Room messages.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.rpc('send_room_message', params: {
        'p_room_id': widget.roomId,
        'p_text': text,
      });
      _controller.clear();
      await _loadMessages(silent: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message could not be sent.'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _exit() async {
    _timer?.cancel();
    try {
      await Supabase.instance.client.rpc('exit_room', params: {'p_room_id': widget.roomId});
    } catch (_) {}
  }

  Future<void> _openRoomInfo() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RoomInfoPage(
          roomId: widget.roomId,
          roomNumber: widget.roomNumber,
          roomName: _roomName,
          profileUrl: widget.profileUrl,
          ownerUid: widget.ownerUid,
          hasPassword: _hasPassword,
          memberCount: _memberCount,
          isOwner: _isOwner,
        ),
      ),
    );
    if (changed == true && mounted) {
      final result = await Supabase.instance.client.rpc('list_rooms', params: {'p_kind': 'my'});
      final rows = (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final mine = rows.where((r) => r['room_id'] == widget.roomId).toList();
      if (mine.isNotEmpty) {
        setState(() {
          _roomName = mine.first['room_name'].toString();
          _hasPassword = mine.first['has_password'] == true;
          _memberCount = (mine.first['member_count'] as num?)?.toInt() ?? _memberCount;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _kickMember(Map<String, dynamic> member) async {
    final uid = member['uid']?.toString();
    final name = member['user_name']?.toString() ?? 'User';
    if (uid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Kick member?'),
        content: Text('Remove $name from this Room?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kick')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('kick_room_member', params: {'p_room_id': widget.roomId, 'p_uid': uid});
      await _loadMembers();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not kick member: $e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _exit();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: InkWell(
            onTap: _openRoomInfo,
            child: Row(
              children: [
                CircleAvatar(radius: 17, backgroundColor: AppColors.border, backgroundImage: widget.profileUrl.isNotEmpty ? NetworkImage(widget.profileUrl) : null, child: widget.profileUrl.isEmpty ? const Icon(Icons.forum_outlined, size: 18) : null),
                const SizedBox(width: 8),
                Flexible(child: Text(_roomName, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 7),
                Text('#' + widget.roomNumber.toString(), style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                const SizedBox(width: 7),
                const Icon(Icons.people_outline, size: 17),
                const SizedBox(width: 3),
                Text(_memberCount.toString(), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(child: Text('No messages in this Room session yet.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final m = _messages[index];
                            final mine = m['sender_id']?.toString() == _myUid;
                            final name = m['sender_name']?.toString() ?? 'User';
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: mine ? AppColors.accent : AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: mine ? AppColors.accent : AppColors.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!mine)
                                      Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                                    if (!mine) const SizedBox(height: 3),
                                    Text(
                                      m['text']?.toString() ?? '',
                                      style: TextStyle(color: mine ? AppColors.textOnAccent : AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: 'Message Room...',
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 5),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoomInfoPage extends StatefulWidget {
  final String roomId;
  final int roomNumber;
  final String roomName;
  final String ownerUid;
  final String profileUrl;
  final bool hasPassword;
  final int memberCount;
  final bool isOwner;

  const RoomInfoPage({
    super.key,
    required this.roomId,
    required this.roomNumber,
    required this.roomName,
    required this.ownerUid,
    this.profileUrl = '',
    required this.hasPassword,
    required this.memberCount,
    required this.isOwner,
  });

  @override
  State<RoomInfoPage> createState() => _RoomInfoPageState();
}

class _RoomInfoPageState extends State<RoomInfoPage> {
  Future<File?> _pickRoomImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 900, maxHeight: 900);
    return x == null ? null : File(x.path);
  }
  late String _name;
  late bool _hasPassword;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _name = widget.roomName;
    _hasPassword = widget.hasPassword;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final result = await Supabase.instance.client.rpc('get_room_members', params: {'p_room_id': widget.roomId});
      if (mounted) {
        setState(() {
          _members = (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editRoom() async {
    String? newProfileUrl;
    final nameController = TextEditingController(text: _name);
    final passwordController = TextEditingController();
    bool changePassword = false;
    bool busy = false;
    bool uploading = false;

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, maxLength: 40, decoration: const InputDecoration(labelText: 'Room name')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Password'),
                subtitle: Text(changePassword ? 'Set or change password' : (_hasPassword ? 'Password is enabled' : 'No password')),
                value: changePassword,
                onChanged: (v) => setDialogState(() => changePassword = v),
              ),
              if (changePassword)
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password (empty = public)'),
                ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.border,
                  backgroundImage: (newProfileUrl ?? widget.profileUrl).isNotEmpty ? NetworkImage(newProfileUrl ?? widget.profileUrl) : null,
                  child: (newProfileUrl ?? widget.profileUrl).isEmpty ? const Icon(Icons.forum_outlined) : null,
                ),
                title: const Text('Room profile picture'),
                subtitle: const Text('Owner can set a separate Room photo'),
                trailing: IconButton(
                  icon: uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera_outlined),
                  onPressed: uploading ? null : () async {
                    // Image selection/upload is handled from the existing media pipeline.
                    setDialogState(() => uploading = true);
                    try {
                      final picker = await _pickRoomImage();
                      if (picker != null) {
                        final url = await CloudflareMediaService.uploadImage(picker, folder: 'rooms');
                        setDialogState(() => newProfileUrl = url);
                      }
                    } catch (e) {
                      if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Could not set Room picture: $e'), backgroundColor: AppColors.error));
                    } finally {
                      if (dialogContext.mounted) setDialogState(() => uploading = false);
                    }
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy ? null : () async {
                setDialogState(() => busy = true);
                try {
                  await Supabase.instance.client.rpc('update_room', params: {
                    'p_room_id': widget.roomId,
                    'p_name': nameController.text.trim(),
                    'p_password': passwordController.text,
                    'p_change_password': changePassword,
                    'p_profile_url': newProfileUrl,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (_) {
                  setDialogState(() => busy = false);
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Could not update Room.'), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    passwordController.dispose();

    if (changed == true && mounted) {
      final result = await Supabase.instance.client.rpc('list_rooms', params: {'p_kind': 'my'});
      final rows = (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final mine = rows.where((r) => r['room_id'] == widget.roomId).toList();
      if (mine.isNotEmpty) {
        setState(() {
          _name = mine.first['room_name'].toString();
          _hasPassword = mine.first['has_password'] == true;
        });
      }
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Room #'+widget.roomNumber.toString())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              if (widget.isOwner)
                IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit Room', onPressed: _editRoom),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('#'+widget.roomNumber.toString(), style: const TextStyle(color: AppColors.textTertiary)),
              const SizedBox(width: 14),
              Icon(_hasPassword ? Icons.lock_outline : Icons.public, size: 18),
              const SizedBox(width: 5),
              Text(_hasPassword ? 'Private' : 'Public'),
              const SizedBox(width: 14),
              const Icon(Icons.people_outline, size: 18),
              const SizedBox(width: 5),
              Text(_members.length.toString() + ' in room'),
            ],
          ),
          const SizedBox(height: 20),
          const Text('People in this Room', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_members.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('No active members.'))
          else
            ..._members.map(
              (m) {
                final isMe = m['uid'] == Supabase.instance.client.auth.currentUser?.id;
                return ListTile(
                leading: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfilePage(isOwnProfile: m['uid'] == Supabase.instance.client.auth.currentUser?.id, otherUser: m['uid']),
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundImage: (m['profile_url']?.toString().isNotEmpty ?? false)
                        ? NetworkImage(m['profile_url'].toString())
                        : null,
                    child: (m['profile_url']?.toString().isNotEmpty ?? false) ? null : const Icon(Icons.person),
                  ),
                ),
                title: GestureDetector(
                  onLongPress: widget.isOwner && !isMe ? () => _kickMember(m) : null,
                  child: Text(m['user_name']?.toString() ?? 'User'),
                ),
                onLongPress: widget.isOwner && !isMe ? () => _kickMember(m) : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(isOwnProfile: m['uid'] == Supabase.instance.client.auth.currentUser?.id, otherUser: m['uid']),
                  ),
                ),
              );
              },
            ),
        ],
      ),
    );
  }
}
