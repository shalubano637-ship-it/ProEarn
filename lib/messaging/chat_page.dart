// =============================================================================
// PRO EARN — Chat page (one-to-one) — v2 redesign
// -----------------------------------------------------------------------------
// Finds-or-creates the conversation via get_or_create_conversation (server
// enforces sorted participant order + no self-messaging), then subscribes
// to a realtime stream of messages for that conversation. Sending goes
// through send_message, which verifies the caller is actually a
// participant before inserting — a client can never post a message into a
// conversation it isn't part of, or spoof senderId.
//
// EPHEMERAL VIEW: only messages sent after MY OWN "clearedAt" cutoff are
// shown — see supabase_schema_ephemeral_chat.sql. This is per-user, so the
// other participant's view is unaffected by mine clearing when the app
// backgrounds (see main.dart's app-lifecycle observer for where that
// clearing actually gets triggered).
//
// v2 additions (see supabase/migrations/2026_chat_redesign.sql for the
// schema/RPCs this depends on — run that migration first):
//   - Day-month date separators between messages sent on different days.
//   - Long-press a message: Reply / Copy / Forward / Remove (+ Report on
//     the other person's messages) — the sheet also shows exactly when
//     that message was sent.
//   - Remove on my own message = delete_message_for_everyone (both sides
//     see "Message removed"). Remove on their message = hide_message_for_me
//     (only disappears from MY view — the sender's copy is untouched).
//   - Camera / gallery send: pick → preview → on-device moderation check
//     → ImgBB upload → send. Images render as a small thumbnail in the
//     bubble; tap to view full size.
//   - Gift icon next to the text bar opens the owned-gifts sheet (same
//     grid as the Bag) with a "watch ad for random gift" shortcut.
//   - Settings icon (AppBar) → mute this person's notifications / block /
//     report, on a dedicated page.
// =============================================================================

import 'package:universal_io/universal_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../theme/theme.dart';
import '../service.dart';
import 'chat_settings_page.dart';
import 'chat_image_preview_page.dart';
import 'chat_multi_image_preview_page.dart';
import 'chat_gift_sheet.dart';
import 'messages_list_page.dart';

class ChatPage extends StatefulWidget {
  final String otherUid;
  final String otherUserName;

  const ChatPage({super.key, required this.otherUid, required this.otherUserName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  // Reply preview tap → scroll to and briefly highlight the original
  // message. Keyed by message id so we can find its RenderObject
  // regardless of where it currently sits in the (variable-height) list.
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, int> _messageFlatIndex = {}; // messageId -> its index in `groups`, refreshed every build
  int _lastGroupsCount = 0;
  String? _lastSeenMessageId; // last message id we've already auto-scrolled for — see the check in build()
  String? _highlightedMessageId;

  Future<void> _scrollToMessage(String messageId) async {
    BuildContext? ctx = _messageKeys[messageId]?.currentContext;

    if (ctx == null && _scrollController.hasClients) {
      // Not built yet — almost certainly off-screen, outside
      // ListView.builder's lazy cacheExtent, so Scrollable.ensureVisible
      // has nothing to find. Jump to a proportional ESTIMATE of where it
      // should be first (index / total messages × max scroll extent) so
      // it enters the build range, then look again after a frame.
      final index = _messageFlatIndex[messageId];
      final total = _lastGroupsCount;
      if (index != null && total > 1) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final estimated = maxExtent * (index / (total - 1));
        _scrollController.jumpTo(estimated.clamp(0, maxExtent));
        await Future.delayed(const Duration(milliseconds: 80));
        ctx = _messageKeys[messageId]?.currentContext;
      }
    }

    if (ctx == null) return; // still nothing — off-screen and estimate missed; give up quietly
    await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.5);
    if (!mounted) return;
    setState(() { _highlightedMessageId = messageId; });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() { _highlightedMessageId = null; });
      }
    });
  }

  String? _conversationId;
  DateTime? _myClearedAt; // messages before this are hidden from MY view only
  bool _isSending = false;
  String? _loadError;
  Map<String, dynamic>? _replyingTo;
  // Created ONCE (in _initConversation, right after _conversationId is
  // known) instead of inline in build(). A stream built inline gets
  // recreated — a brand-new realtime subscription — on every rebuild
  // (e.g. every _isSending setState while sending), which is exactly
  // what caused messages to flash twice until a manual refresh. Same
  // root cause the coin-balance indicator had, fixed the same way.
  Stream<List<Map<String, dynamic>>>? _messagesStream;

  // Block status — checked both directions:
  //   _iBlockedThem: read from MY OWN row's blockedUsers (always readable).
  //   _theyBlockedMe: server-side RPC (is_blocked_by_user) — can't read
  //     someone else's blockedUsers array directly, only ask a yes/no.
  bool _iBlockedThem = false;
  bool _theyBlockedMe = false;
  bool _isUnblocking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConversation();
    _loadBlockStatus();
    Supabase.instance.client.rpc('set_presence', params: {
      'p_screen': 'chat',
      'p_chatting_with_uid': widget.otherUid,
    }).catchError((e) => debugPrint('set_presence failed: $e'));
  }

  Future<void> _loadBlockStatus() async {
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    if (myUid == null) return;

    try {
      final myRow = await Supabase.instance.client
          .from(kUsersCollection)
          .select('blockedUsers')
          .eq('uid', myUid)
          .maybeSingle();
      final myBlockedList = (myRow?['blockedUsers'] as List?)?.cast<String>() ?? [];

      final blockedByThem = await Supabase.instance.client
          .rpc('is_blocked_by_user', params: {'p_target_uid': widget.otherUid});

      if (!mounted) return;
      setState(() {
        _iBlockedThem = myBlockedList.contains(widget.otherUid);
        _theyBlockedMe = blockedByThem == true;
      });
    } catch (e) {
      debugPrint("Block status check failed: $e");
    }
  }

  Future<void> _unblock() async {
    setState(() { _isUnblocking = true; });
    try {
      await Supabase.instance.client.rpc('unblock_user', params: {
        'p_user_id': Supabase.instance.client.auth.currentUser!.id,
        'p_blocked_id': widget.otherUid,
      });
      if (mounted) setState(() { _iBlockedThem = false; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't unblock — please try again."), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() { _isUnblocking = false; });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      Supabase.instance.client.rpc('set_presence', params: {'p_screen': 'other'})
          .catchError((e) => debugPrint('set_presence failed: $e'));
    } else if (state == AppLifecycleState.resumed) {
      // Still on this chat page after backgrounding — re-assert presence
      // so message pushes stay suppressed for this exact conversation.
      Supabase.instance.client.rpc('set_presence', params: {
        'p_screen': 'chat',
        'p_chatting_with_uid': widget.otherUid,
      }).catchError((e) => debugPrint('set_presence failed: $e'));
    }
  }

  Future<void> _initConversation() async {
    try {
      final myUid = Supabase.instance.client.auth.currentUser!.id;
      final id = await Supabase.instance.client
          .rpc('get_or_create_conversation', params: {'p_other_uid': widget.otherUid});

      final conv = await Supabase.instance.client
          .from('conversations')
          .select()
          .eq('id', id)
          .single();

      final bool iAmA = conv['participantA'] == myUid;
      final clearedAtRaw = iAmA ? conv['clearedAtA'] : conv['clearedAtB'];

      if (mounted) {
        setState(() {
          _conversationId = id as String;
          _myClearedAt = clearedAtRaw != null ? DateTime.parse(clearedAtRaw.toString()) : null;
          _messagesStream = Supabase.instance.client
              .from('messages')
              .stream(primaryKey: ['id'])
              .eq('conversationId', id)
              .order('createdAt', ascending: true);
        });
      }
      // Opening the chat = read. Clears the yellow unread dot on
      // MessagesListPage for this conversation.
      Supabase.instance.client
          .rpc('mark_conversation_read', params: {'p_conversation_id': id})
          .catchError((e) => debugPrint('mark_conversation_read failed: $e'));
    } catch (e) {
      debugPrint("Couldn't open chat: $e");
      if (mounted) setState(() { _loadError = "Couldn't open this chat — please try again."; });
    }
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    if (_iBlockedThem || _theyBlockedMe) return; // belt-and-suspenders — UI already hides the input bar
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null) return;
    if (_conversationId == null || _isSending) return;

    setState(() { _isSending = true; });
    _messageController.clear();
    final replyId = _replyingTo?['id'] as String?;
    setState(() { _replyingTo = null; });

    try {
      await Supabase.instance.client.rpc('send_message', params: {
        'p_conversation_id': _conversationId,
        'p_text': text.isEmpty ? null : text,
        'p_image_url': imageUrl,
        'p_reply_to_message_id': replyId,
      });

      // Non-blocking — a notification failure shouldn't affect the
      // message send itself, which already succeeded above.
      sendNotification(
        targetOwnerId: widget.otherUid,
        type: 'message',
        message: imageUrl != null ? 'Someone sent you a photo' : 'Someone texted you',
      );

      // I obviously "read" my own message — keeps MY unread dot from
      // falsely lighting up on MessagesListPage after I send.
      Supabase.instance.client
          .rpc('mark_conversation_read', params: {'p_conversation_id': _conversationId})
          .catchError((e) => debugPrint('mark_conversation_read failed: $e'));
    } catch (e) {
      debugPrint("send_message failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Message failed to send: $e"), backgroundColor: AppColors.error),
        );
        if (text.isNotEmpty) _messageController.text = text; // restore so the user doesn't lose what they typed
      }
    } finally {
      if (mounted) setState(() { _isSending = false; });
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null || !mounted) return;

      final url = await showChatImagePreview(context, File(picked.path));
      if (url != null) {
        await _sendMessage(imageUrl: url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open camera/gallery."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // Gallery multi-select — up to 20 photos at once. Each is compressed +
  // moderated in chat_multi_image_preview_page.dart, then sent as
  // separate send_message calls back-to-back (no new column/RPC param
  // needed) — the tight timing is exactly what makes the receiving side
  // group them into one album tile (see _groupConsecutiveImages below).
  Future<void> _pickAndSendMultipleImages() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 90, limit: 20);
      if (picked.isEmpty || !mounted) return;

      var files = picked.map((x) => File(x.path)).toList();
      if (files.length > 20) {
        files = files.sublist(0, 20);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Only the first 20 photos were kept.")),
        );
      }

      final urls = await showChatMultiImagePreview(context, files);
      if (urls == null || urls.isEmpty || !mounted) return;

      for (final url in urls) {
        await _sendMessage(imageUrl: url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open gallery."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _startReply(Map<String, dynamic> msg) {
    setState(() { _replyingTo = msg; });
  }

  void _cancelReply() {
    setState(() { _replyingTo = null; });
  }

  void _copyText(Map<String, dynamic> msg) {
    final text = (msg['text'] ?? '') as String;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No text to copy.")));
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied.")));
  }

  void _forwardMessage(Map<String, dynamic> msg) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagesListPage(
          forwardText: msg['text'] as String?,
          forwardImageUrl: msg['imageUrl'] as String?,
        ),
      ),
    );
  }

  /// Returns true only if the message was actually removed (false if the
  /// person cancelled the confirmation, or the RPC call failed).
  Future<bool> _removeForEveryone(Map<String, dynamic> msg, {bool skipConfirm = false}) async {
    if (!skipConfirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("Remove message?"),
          content: const Text("This removes it for both you and the other person. This can't be undone."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Remove", style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
      if (confirmed != true) return false;
    }

    try {
      await Supabase.instance.client.rpc('delete_message_for_everyone', params: {'p_message_id': msg['id']});
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't remove — please try again."), backgroundColor: AppColors.error),
        );
      }
      return false;
    }
  }

  Future<bool> _removeForMe(Map<String, dynamic> msg, {bool skipConfirm = false}) async {
    try {
      await Supabase.instance.client.rpc('hide_message_for_me', params: {'p_message_id': msg['id']});
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't remove — please try again."), backgroundColor: AppColors.error),
        );
      }
      return false;
    }
  }

  void _openReportMessageSheet(Map<String, dynamic> msg) {
    const reportReasons = [
      "Spam or Misleading",
      "Hate Speech or Violence",
      "Harassment or Bullying",
      "Nudity or Sexual Content",
      "Intellectual Property Violation",
    ];
    String? selectedReason;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final systemBottom = MediaQuery.of(context).padding.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset > 0 ? bottomInset + 24 : systemBottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Report this message", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    hint: const Text("Select a reason"),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: AppRadius.smRadius, borderSide: BorderSide.none),
                    ),
                    items: reportReasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (v) => setSheetState(() { selectedReason = v; }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedReason == null ? AppColors.textTertiary : AppColors.error,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                      ),
                      onPressed: selectedReason == null ? null : () async {
                        Navigator.pop(sheetContext);
                        try {
                          await Supabase.instance.client.from(kReportsCollection).insert({
                            'reportedBy': Supabase.instance.client.auth.currentUser!.id,
                            'reportedUserId': msg['senderId'],
                            'targetMessageId': msg['id'],
                            'messageSnapshot': msg['text'],
                            'reason': selectedReason,
                            'source': 'chat_message',
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Report submitted — thank you.")),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Couldn't submit report — please try again."), backgroundColor: AppColors.error),
                            );
                          }
                        }
                      },
                      child: const Text("SUBMIT REPORT", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Long-pressing the ALBUM TILE (not a specific photo inside it) —
  // Reply/Forward/Remove apply to the WHOLE group here. For per-photo
  // actions (remove just one image, reply/forward just one), see the
  // menu inside _ImageGroupViewerPage instead (opened by tapping the tile).
  void _showAlbumOptions(List<Map<String, dynamic>> group, bool isMe) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 14, bottom: 6),
              child: Text("This album", style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text("Reply"),
              onTap: () { Navigator.pop(sheetContext); _startReply(group.last); },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: Text("Forward all (${group.length})"),
              onTap: () { Navigator.pop(sheetContext); _forwardAlbum(group); },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: isMe ? AppColors.error : AppColors.textPrimary),
              title: Text(
                isMe ? "Remove all for everyone" : "Remove all for me",
                style: TextStyle(color: isMe ? AppColors.error : null),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _removeAlbum(group, isMe);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _forwardAlbum(List<Map<String, dynamic>> group) {
    final urls = group.map((m) => m['imageUrl'] as String).toList();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MessagesListPage(forwardImageUrls: urls)),
    );
  }

  Future<void> _removeAlbum(List<Map<String, dynamic>> group, bool isMe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Remove all ${group.length} photos?"),
        content: Text(isMe
            ? "This removes them for both you and the other person. This can't be undone."
            : "This removes them from your view only."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Remove", style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final msg in group) {
      if (isMe) {
        await _removeForEveryone(msg, skipConfirm: true);
      } else {
        await _removeForMe(msg, skipConfirm: true);
      }
    }
  }

  void _showMessageOptions(Map<String, dynamic> msg, bool isMe, {bool isGift = false}) {
    final createdAt = DateTime.tryParse(msg['createdAt']?.toString() ?? '');
    final hasText = ((msg['text'] ?? '') as String).isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (createdAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Text(
                    "Sent ${_formatDayMonth(createdAt)} at ${_formatTime(createdAt)}",
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text("Reply"),
                onTap: () { Navigator.pop(sheetContext); _startReply(msg); },
              ),
              // A gift receipt isn't a regular message — nothing to copy,
              // forward, remove, or report about it. Reply is the only
              // action that makes sense (e.g. "thanks for the gift!").
              if (!isGift) ...[
                if (hasText)
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text("Copy"),
                    onTap: () { Navigator.pop(sheetContext); _copyText(msg); },
                  ),
                ListTile(
                  leading: const Icon(Icons.forward),
                  title: const Text("Forward"),
                  onTap: () { Navigator.pop(sheetContext); _forwardMessage(msg); },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: isMe ? AppColors.error : AppColors.textPrimary),
                  title: Text(
                    isMe ? "Remove for everyone" : "Remove for me",
                    style: TextStyle(color: isMe ? AppColors.error : null),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    isMe ? _removeForEveryone(msg) : _removeForMe(msg);
                  },
                ),
                if (!isMe)
                  ListTile(
                    leading: const Icon(Icons.flag_outlined, color: AppColors.error),
                    title: const Text("Report", style: TextStyle(color: AppColors.error)),
                    onTap: () { Navigator.pop(sheetContext); _openReportMessageSheet(msg); },
                  ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _viewImageFullscreen(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(
            child: InteractiveViewer(
              child: GlobalCachedImage(imageUrl: imageUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  // Gallery-group tap → swipeable fullscreen viewer starting at whichever
  // thumbnail was tapped. Passes the actual message objects (not just
  // URLs) so the viewer's per-photo menu can Reply/Forward/Remove that
  // ONE specific image — removing it here actually deletes just that
  // message, which is why "isGift"/isMe etc. need the real message data.
  void _viewImageGroupFullscreen(List<Map<String, dynamic>> group, int startIndex) {
    final myUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageGroupViewerPage(
          group: group,
          initialIndex: startIndex,
          myUid: myUid,
          onReply: _startReply,
          onForward: _forwardMessage,
          onRemoveForEveryone: _removeForEveryone,
          onRemoveForMe: _removeForMe,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    Supabase.instance.client.rpc('set_presence', params: {'p_screen': 'other'})
        .catchError((e) => debugPrint('set_presence failed: $e'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUserName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Chat settings",
            onPressed: () async {
              final result = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatSettingsPage(otherUid: widget.otherUid, otherUserName: widget.otherUserName),
                ),
              );
              if (result == 'blocked') {
                await _loadBlockStatus();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("${widget.otherUserName} blocked.")),
                  );
                }
              } else if (result == 'reported') {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Report submitted — thank you.")),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadError != null
                ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_loadError!)))
                : _conversationId == null
                    ? const Center(child: CircularProgressIndicator())
                    : StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _messagesStream,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          // Ephemeral filter — messages sent before my own
                          // clearedAt are hidden from my view only. The
                          // underlying rows are untouched, so the other
                          // participant (whose clearedAt is independent)
                          // still sees everything normally. Also hides
                          // anything I've individually "removed for me".
                          final allMessages = snapshot.data!;
                          final messages = allMessages.where((m) {
                            final createdAt = DateTime.parse(m['createdAt'].toString());
                            if (_myClearedAt != null && !createdAt.isAfter(_myClearedAt!)) return false;
                            final deletedFor = (m['deletedFor'] as List?)?.cast<String>() ?? const [];
                            if (deletedFor.contains(myUid)) return false;
                            return true;
                          }).toList();

                          // Lookup for reply-preview snippets — by id,
                          // from whatever's already loaded for this chat.
                          final byId = {for (final m in allMessages) m['id'] as String: m};
                          _messageKeys.removeWhere((id, _) => !byId.containsKey(id)); // drop keys for messages no longer around (e.g. removed)
                          _messageFlatIndex.removeWhere((id, _) => !byId.containsKey(id));

                          if (messages.isEmpty) {
                            return const Center(child: Text("Say hi 👋"));
                          }

                          // Auto-scroll-to-bottom, but ONLY when a genuinely NEW
                          // message actually arrived — not on every rebuild of this
                          // page (e.g. the highlight setState from tapping a reply
                          // preview). Without this check, that unconditional jumpTo
                          // was firing on ANY setState anywhere in the page and
                          // immediately snapping back to the bottom, undoing
                          // _scrollToMessage's careful scroll-to-target right after
                          // it ran — exactly why "scroll up hota tha par exactly wahi
                          // jagah nahi rukta tha".
                          final String? latestId = messages.last['id'] as String?;
                          if (latestId != _lastSeenMessageId) {
                            _lastSeenMessageId = latestId;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                              }
                            });
                          }

                          final groups = _groupConsecutiveImages(messages);
                          _lastGroupsCount = groups.length;

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: groups.length,
                            itemBuilder: (context, index) {
                              final group = groups[index];
                              final bool isAlbum = group.length > 1;
                              final createdAt = DateTime.parse(group.first['createdAt'].toString());
                              final prevCreatedAt = index == 0
                                  ? null
                                  : DateTime.parse(groups[index - 1].last['createdAt'].toString());
                              final showDateSeparator = prevCreatedAt == null || !_isSameDay(createdAt, prevCreatedAt);

                              if (isAlbum) {
                                final bool isMe = group.first['senderId'] == myUid;
                                final imageUrls = group.map((m) => m['imageUrl'] as String).toList();
                                // Reply/Forward/Remove on a long-pressed album apply to
                                // its LAST photo (arbitrary but consistent pick — there's
                                // no single-message id for a whole album since it's just
                                // several ordinary image messages grouped visually).
                                final lastMsgInGroup = group.last;
                                final String groupKeyId = lastMsgInGroup['id'] as String;
                                _messageKeys.putIfAbsent(groupKeyId, () => GlobalKey());
                                _messageFlatIndex[groupKeyId] = index;

                                return Column(
                                  key: _messageKeys[groupKeyId],
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (showDateSeparator) _DateSeparator(date: createdAt),
                                    Align(
                                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: GestureDetector(
                                        onLongPress: () => _showAlbumOptions(group, isMe),
                                        child: _ImageGroupTile(
                                          imageUrls: imageUrls,
                                          onOpen: (startIndex) => _viewImageGroupFullscreen(group, startIndex),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              final msg = group.first;

                              final bool isMe = msg['senderId'] == myUid;
                              final bool removedForEveryone = msg['deletedForEveryone'] == true;
                              final replyToId = msg['replyToMessageId'] as String?;
                              final repliedMsg = replyToId != null ? byId[replyToId] : null;
                              // Gift messages (sent via chat_gift_sheet.dart) are tagged by
                              // their "🎁 " text prefix — there's no separate message
                              // "type" column, so this is the one signal we have. They get
                              // a smaller thumbnail and no Forward/Remove menu (it's a gift
                              // receipt, not a regular photo — nothing to forward/delete).
                              final bool isGift = ((msg['text'] ?? '') as String).startsWith('🎁');
                              final String msgId = msg['id'] as String;
                              final bool isHighlighted = msgId == _highlightedMessageId;
                              _messageKeys.putIfAbsent(msgId, () => GlobalKey());
                              _messageFlatIndex[msgId] = index;

                              return Column(
                                key: _messageKeys[msgId],
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showDateSeparator) _DateSeparator(date: createdAt),
                                  GestureDetector(
                                    onLongPress: removedForEveryone ? null : () => _showMessageOptions(msg, isMe, isGift: isGift),
                                    child: Align(
                                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: (msg['imageUrl'] != null && !removedForEveryone) ? 4 : 14,
                                          vertical: (msg['imageUrl'] != null && !removedForEveryone) ? 4 : 10,
                                        ),
                                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                        decoration: BoxDecoration(
                                          color: removedForEveryone
                                              ? AppColors.surface
                                              : isHighlighted
                                                  ? AppColors.warning.withOpacity(0.35)
                                                  : (isMe ? AppColors.accent : AppColors.surfaceElevated),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: removedForEveryone
                                            ? const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                child: Text(
                                                  "Message removed",
                                                  style: TextStyle(color: AppColors.textTertiary, fontStyle: FontStyle.italic),
                                                ),
                                              )
                                            : Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (repliedMsg != null)
                                                    GestureDetector(
                                                      onTap: () => _scrollToMessage(repliedMsg['id'] as String),
                                                      child: _ReplyPreviewChip(message: repliedMsg, isMe: isMe),
                                                    ),
                                                  if (msg['imageUrl'] != null)
                                                    GestureDetector(
                                                      onTap: isGift ? null : () => _viewImageFullscreen(msg['imageUrl'] as String),
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(12),
                                                        child: GlobalCachedImage(
                                                          imageUrl: msg['imageUrl'] as String,
                                                          width: isGift ? 72 : 160,
                                                          height: isGift ? 72 : 160,
                                                          fit: isGift ? BoxFit.contain : BoxFit.cover,
                                                        ),
                                                      ),
                                                    ),
                                                  if (((msg['text'] ?? '') as String).isNotEmpty)
                                                    Padding(
                                                      padding: EdgeInsets.only(top: msg['imageUrl'] != null ? 6 : 0, left: msg['imageUrl'] != null ? 6 : 0, right: msg['imageUrl'] != null ? 6 : 0),
                                                      child: Text(
                                                        msg['text'] ?? '',
                                                        style: TextStyle(color: isMe ? AppColors.textOnAccent : AppColors.textPrimary),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
          ),
          if (_replyingTo != null) _ReplyComposerBar(message: _replyingTo!, onCancel: _cancelReply),
          if (_iBlockedThem || _theyBlockedMe)
            _BlockedBanner(
              theyBlockedMe: _theyBlockedMe,
              otherUserName: widget.otherUserName,
              isUnblocking: _isUnblocking,
              onUnblock: _iBlockedThem ? _unblock : null,
            )
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.camera_alt_outlined),
                      tooltip: "Camera",
                      onPressed: () => _pickAndSendImage(ImageSource.camera),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: "Message...",
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.image_outlined),
                      tooltip: "Gallery",
                      onPressed: _pickAndSendMultipleImages,
                    ),
                    IconButton(
                      icon: const Icon(Icons.card_giftcard_outlined),
                      tooltip: "Send a gift",
                      onPressed: _conversationId == null
                          ? null
                          : () => showChatGiftSheet(
                                context,
                                otherUid: widget.otherUid,
                                otherUserName: widget.otherUserName,
                                conversationId: _conversationId!,
                              ),
                    ),
                    IconButton(
                      icon: _isSending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send),
                      tooltip: "Send message",
                      onPressed: _isSending ? null : () => _sendMessage(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

// Groups consecutive plain-image messages (same sender, no text, not a
// reply, sent within a few seconds of each other) into one "album" — a
// gallery multi-send fires several send_message calls back-to-back, and
// this is how the receiving side turns that burst into a single grid
// tile instead of N separate bubbles. No schema/RPC change needed: pure
// client-side grouping by timing + shape, same trick messaging apps use.
List<List<Map<String, dynamic>>> _groupConsecutiveImages(List<Map<String, dynamic>> messages) {
  bool isPlainImage(Map<String, dynamic> m) =>
      m['imageUrl'] != null &&
      ((m['text'] ?? '') as String).isEmpty &&
      m['replyToMessageId'] == null &&
      m['deletedForEveryone'] != true;

  final groups = <List<Map<String, dynamic>>>[];
  for (final msg in messages) {
    if (groups.isNotEmpty && isPlainImage(msg)) {
      final lastGroup = groups.last;
      final lastMsg = lastGroup.last;
      final sameSender = lastMsg['senderId'] == msg['senderId'];
      final closeInTime = DateTime.parse(msg['createdAt'].toString())
          .difference(DateTime.parse(lastMsg['createdAt'].toString()))
          .abs() <= const Duration(seconds: 10);
      if (isPlainImage(lastMsg) && sameSender && closeInTime) {
        lastGroup.add(msg);
        continue;
      }
    }
    groups.add([msg]);
  }
  return groups;
}

const List<String> _kShortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDayMonth(DateTime dt) {
  final now = DateTime.now();
  if (_isSameDay(dt, now)) return "Today";
  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(dt, yesterday)) return "Yesterday";
  return "${dt.day} ${_kShortMonths[dt.month - 1]}";
}

String _formatTime(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? "PM" : "AM";
  return "$hour12:$minute $period";
}

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.pillRadius),
          child: Text(_formatDayMonth(date), style: const TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Small quoted-message preview shown inside a bubble when that message
/// is a reply to an earlier one.
class _ReplyPreviewChip extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  const _ReplyPreviewChip({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final removed = message['deletedForEveryone'] == true;
    final hasImage = message['imageUrl'] != null && !removed;
    final text = removed ? "Message removed" : ((message['text'] ?? (hasImage ? "📷 Photo" : '')) as String);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: (isMe ? AppColors.textOnAccent : AppColors.textPrimary).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: isMe ? AppColors.textOnAccent : AppColors.accent, width: 3)),
      ),
      child: Text(
        text.isEmpty ? "📷 Photo" : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: (isMe ? AppColors.textOnAccent : AppColors.textPrimary).withOpacity(0.85)),
      ),
    );
  }
}

/// The "replying to…" bar shown above the text field while composing a
/// reply, with an X to cancel it.
class _ReplyComposerBar extends StatelessWidget {
  final Map<String, dynamic> message;
  final VoidCallback onCancel;
  const _ReplyComposerBar({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final removed = message['deletedForEveryone'] == true;
    final hasImage = message['imageUrl'] != null && !removed;
    final text = removed ? "Message removed" : ((message['text'] ?? '') as String);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.isEmpty ? (hasImage ? "📷 Photo" : "Message") : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: "Cancel reply",
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Replaces the message input bar whenever either side has blocked the
// other. Two distinct copies, per which side you're on:
//   - I blocked them: "You blocked this user, please unblock first" +
//     an Unblock button (this is the ONLY place besides Chat Settings
//     that can undo it).
//   - They blocked me: "The other user has blocked you" — no button,
//     since only the blocker can undo their own block.
// Either way, no message can be sent while this banner is showing (the
// input row itself isn't even built — see build() above).
// =============================================================================
class _BlockedBanner extends StatelessWidget {
  final bool theyBlockedMe;
  final String otherUserName;
  final bool isUnblocking;
  final VoidCallback? onUnblock;

  const _BlockedBanner({
    required this.theyBlockedMe,
    required this.otherUserName,
    required this.isUnblocking,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.block, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    theyBlockedMe
                        ? "$otherUserName has blocked you."
                        : "You blocked this user, please unblock first.",
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (onUnblock != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: isUnblocking ? null : onUnblock,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.warning),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                  ),
                  child: isUnblocking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Unblock", style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Grid preview for a gallery multi-send "album" (see
// _groupConsecutiveImages above). Shows up to 4 thumbnails in a 2x2 grid;
// a 5th-or-more count badge appears on the last cell ("+N") like most
// chat apps. Tapping any thumbnail opens the swipeable fullscreen viewer
// starting at that exact photo.
// =============================================================================
class _ImageGroupTile extends StatelessWidget {
  final List<String> imageUrls;
  final void Function(int startIndex) onOpen;
  const _ImageGroupTile({required this.imageUrls, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final visible = imageUrls.take(4).toList();
    final remaining = imageUrls.length - visible.length;

    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final isLastWithMore = remaining > 0 && i == visible.length - 1;
            return GestureDetector(
              onTap: () => onOpen(i),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GlobalCachedImage(imageUrl: visible[i], fit: BoxFit.cover),
                  if (isLastWithMore)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Text("+$remaining", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ImageGroupViewerPage extends StatefulWidget {
  final List<Map<String, dynamic>> group;
  final int initialIndex;
  final String myUid;
  final void Function(Map<String, dynamic> msg) onReply;
  final void Function(Map<String, dynamic> msg) onForward;
  final Future<bool> Function(Map<String, dynamic> msg) onRemoveForEveryone;
  final Future<bool> Function(Map<String, dynamic> msg) onRemoveForMe;

  const _ImageGroupViewerPage({
    required this.group,
    required this.initialIndex,
    required this.myUid,
    required this.onReply,
    required this.onForward,
    required this.onRemoveForEveryone,
    required this.onRemoveForMe,
  });

  @override
  State<_ImageGroupViewerPage> createState() => _ImageGroupViewerPageState();
}

class _ImageGroupViewerPageState extends State<_ImageGroupViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;
  late List<Map<String, dynamic>> _group; // local, shrinks as photos get removed one at a time

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _group = List.of(widget.group);
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Per-PHOTO menu (top-right of the currently viewed image) — Reply,
  // Forward, Remove apply to just this one. Pops the viewer first so the
  // action's own UI (reply compose bar, forward picker) opens on top of
  // the actual ChatPage, not this fullscreen viewer.
  void _showPhotoMenu(Map<String, dynamic> msg) {
    final bool isMe = msg['senderId'] == widget.myUid;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text("Reply"),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.pop(context); // close viewer
                widget.onReply(msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text("Forward"),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.pop(context);
                widget.onForward(msg);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: isMe ? AppColors.error : AppColors.textPrimary),
              title: Text(
                isMe ? "Remove for everyone" : "Remove for me",
                style: TextStyle(color: isMe ? AppColors.error : null),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                // isMe's version shows its own confirm dialog and only
                // returns true once the RPC actually succeeds — only
                // THEN do we drop it from the local view. Otherwise a
                // cancelled confirm would make the photo vanish from
                // the viewer even though nothing was actually removed.
                final removed = isMe ? await widget.onRemoveForEveryone(msg) : await widget.onRemoveForMe(msg);
                if (!removed || !mounted) return;
                setState(() {
                  _group.removeWhere((m) => m['id'] == msg['id']);
                  if (_group.isEmpty) {
                    Navigator.pop(context); // nothing left to view
                  } else if (_currentIndex >= _group.length) {
                    _currentIndex = _group.length - 1;
                  }
                });
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_group.isEmpty) return const SizedBox.shrink(); // mid-pop after last photo removed
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          "${_currentIndex + 1} / ${_group.length}",
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _group.length,
        onPageChanged: (i) => setState(() { _currentIndex = i; }),
        itemBuilder: (context, i) {
          final msg = _group[i];
          return Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: GlobalCachedImage(imageUrl: msg['imageUrl'] as String, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    tooltip: "Reply / Forward / Remove",
                    onPressed: () => _showPhotoMenu(msg),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
