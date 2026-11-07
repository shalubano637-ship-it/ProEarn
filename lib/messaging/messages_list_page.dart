
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models.dart';
import '../ad_unit_ids.dart';
import '../theme/theme.dart';
import '../service.dart';
import 'chat_page.dart';
import 'message_requests_page.dart';
import '../user_profile_features.dart';
import '../widgets/error_retry_view.dart';

class MessagesListPage extends StatefulWidget {
  final String? forwardText;
  final String? forwardImageUrl;
  final List<String>? forwardImageUrls;

  const MessagesListPage({super.key, this.forwardText, this.forwardImageUrl, this.forwardImageUrls});

  bool get isForwardMode => forwardText != null || forwardImageUrl != null || forwardImageUrls != null;

  @override
  State<MessagesListPage> createState() => _MessagesListPageState();
}

class _MessagesListPageState extends State<MessagesListPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  Future<List<Map<String, dynamic>>>? _conversationsFuture;
  List<Map<String, dynamic>>? _cachedConversations;
  Timer? _inboxRefreshDebounce;
  RealtimeChannel? _chatUpdatesChannel;

  Future<List<Map<String, dynamic>>> _fetchConversations() async {
    final currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    // Inbox rows and pending requests are independent reads.
    final results = await Future.wait([
      Supabase.instance.client
          .from('conversations')
          .select()
          .or('participantA.eq.$currentUid,participantB.eq.$currentUid')
          .order('lastMessageAt', ascending: false),
      Supabase.instance.client
          .from('message_requests')
          .select('conversationId')
          .eq('recipientId', currentUid)
          .eq('status', 'pending'),
    ]);
    final conversations = results[0] as List;
    final requests = results[1] as List;

    final pendingIds = requests.map((r) => r['conversationId'].toString()).toSet();

    return List<Map<String, dynamic>>.from(conversations).where((conv) {
      return !pendingIds.contains(conv['id'].toString());
    }).toList();
  }

  void _refreshConversations() {
    if (!mounted) return;
    setState(() {
      _conversationsFuture = _fetchConversations();
    });
  }

  void _scheduleConversationRefresh() {
    _inboxRefreshDebounce?.cancel();
    _inboxRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _refreshConversations();
    });
  }

  Widget _buildNormalConversationList(List<Map<String, dynamic>> allConversations, String currentUid) {
    final conversations = allConversations.where((conv) {
      final bool iAmA = conv['participantA'] == currentUid;
      final bool hiddenForMe = iAmA ? (conv['hiddenByA'] ?? false) : (conv['hiddenByB'] ?? false);
      return !hiddenForMe;
    }).toList();
    if (conversations.isNotEmpty) {
      return _ConversationsList(
        currentUid: currentUid,
        conversations: conversations,
        query: _query,
        forwardText: widget.forwardText,
        forwardImageUrl: widget.forwardImageUrl,
        forwardImageUrls: widget.forwardImageUrls,
        onChatReturn: _refreshConversations,
      );
    }
    return _FollowedUsersList(
      currentUid: currentUid,
      query: _query,
      forwardText: widget.forwardText,
      forwardImageUrl: widget.forwardImageUrl,
      forwardImageUrls: widget.forwardImageUrls,
    );
  }

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _fetchConversations();
    final client = Supabase.instance.client;
    // Refresh the inbox whenever a conversation or message changes so the most
    // recently active chat moves to the top without reopening the page.
    _chatUpdatesChannel = client.channel('messages-list-${client.auth.currentUser?.id ?? 'user'}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'conversations',
        callback: (_) => _scheduleConversationRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => _scheduleConversationRefresh(),
      )
      ..subscribe();
    _loadBannerAd();
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() { _query = _searchController.text.trim().toLowerCase(); });
      });
    });
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) { if (mounted) setState(() => _isBannerLoaded = true); },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _inboxRefreshDebounce?.cancel();
    _searchController.dispose();
    _bannerAd?.dispose();
    final channel = _chatUpdatesChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (currentUid.isEmpty) {
      return const Scaffold(body: Center(child: Text("Please log in.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isForwardMode ? "Forward to…" : "Messages"),
        actions: [
          if (!widget.isForwardMode)
            IconButton(
              icon: const Icon(Icons.mail_outline),
              tooltip: "Message Requests",
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MessageRequestsPage()),
                );
                _refreshConversations();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isBannerLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _conversationsFuture,
              builder: (context, convSnapshot) {
                if (convSnapshot.hasData) {
                  _cachedConversations = convSnapshot.data;
                }
                final cached = _cachedConversations;
                if (convSnapshot.connectionState == ConnectionState.waiting && cached == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (convSnapshot.hasError && cached == null) {
                  return ErrorRetryView(error: convSnapshot.error, onRetry: _refreshConversations);
                }
                // Keep the existing inbox visible during background refreshes.
                return _buildNormalConversationList(
                  convSnapshot.hasData ? convSnapshot.data! : (cached ?? const []),
                  currentUid,
                );
              },
            ),
          ),        ],
      ),
    );
  }
}

void _openProfile(BuildContext context, String uid) {
  final myUid = Supabase.instance.client.auth.currentUser?.id;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProfilePage(isOwnProfile: uid == myUid, otherUser: uid == myUid ? null : uid),
    ),
  );
}

Future<void> _deleteChatFromList(BuildContext context, String otherUid, String userName, VoidCallback? onReturn) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete chat?'),
      content: Text('Delete the chat with $userName from your Messages list?'),
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
      params: {'p_other_uid': otherUid},
    );
    await Supabase.instance.client.rpc(
      'hide_conversation_for_me',
      params: {'p_conversation_id': conversationId},
    );
    onReturn?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat deleted.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete chat."), backgroundColor: AppColors.error),
      );
    }
  }
}

void _openChat(BuildContext context, String otherUid, String otherUserName, {VoidCallback? onReturn}) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ChatPage(otherUid: otherUid, otherUserName: otherUserName)),
  ).then((_) => onReturn?.call());
}

Future<void> _forwardTo(
  BuildContext context, {
  required String otherUid,
  required String otherUserName,
  String? forwardText,
  String? forwardImageUrl,
  List<String>? forwardImageUrls,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final conversationId = await Supabase.instance.client
        .rpc('get_or_create_conversation', params: {'p_other_uid': otherUid});

    if (forwardImageUrls != null && forwardImageUrls.isNotEmpty) {
      for (final url in forwardImageUrls) {
        await Supabase.instance.client.rpc('send_message', params: {
          'p_conversation_id': conversationId,
          'p_text': null,
          'p_image_url': url,
        });
      }
    } else {
      await Supabase.instance.client.rpc('send_message', params: {
        'p_conversation_id': conversationId,
        'p_text': forwardText,
        'p_image_url': forwardImageUrl,
      });
    }

    Supabase.instance.client
        .rpc('mark_conversation_read', params: {'p_conversation_id': conversationId})
        .catchError((e) => debugPrint('mark_conversation_read failed: $e'));

    sendNotification(targetOwnerId: otherUid, type: 'message', message: 'Someone forwarded you a message');

    if (context.mounted) {
      Navigator.pop(context); // close the loading dialog
      Navigator.pop(context); // close the forward picker
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Forwarded to $otherUserName")),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context); // close the loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't forward — please try again."), backgroundColor: AppColors.error),
      );
    }
  }
}

class _ConversationsList extends StatefulWidget {
  final String currentUid;
  final List<Map<String, dynamic>> conversations;
  final String query;
  final String? forwardText;
  final String? forwardImageUrl;
  final List<String>? forwardImageUrls;
  final VoidCallback? onChatReturn;

  const _ConversationsList({
    required this.currentUid,
    required this.conversations,
    required this.query,
    this.forwardText,
    this.forwardImageUrl,
    this.forwardImageUrls,
    this.onChatReturn,
  });

  bool get isForwardMode => forwardText != null || forwardImageUrl != null || forwardImageUrls != null;

  @override
  State<_ConversationsList> createState() => _ConversationsListState();
}

class _ConversationsListState extends State<_ConversationsList> {
  late Future<Map<String, Map<String, dynamic>>> _profilesFuture;
  late Future<Map<String, int>> _unreadCountsFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = _fetchOtherParticipantProfiles();
    _unreadCountsFuture = _fetchUnreadCounts();
  }

  Future<Map<String, int>> _fetchUnreadCounts() async {
    if (widget.isForwardMode) return {};
    try {
      // A single RPC returns counts for every conversation, avoiding an
      // individual messages SELECT for every visible inbox row.
      final rows = await Supabase.instance.client.rpc('get_unread_message_counts');
      return {
        for (final row in (rows as List))
          row['conversation_id'].toString():
              ((row['unread_count'] as num?)?.toInt() ?? 0),
      };
    } catch (e, stackTrace) {
      debugPrint('Could not load inbox unread counts: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<int?> _unreadCountFuture(String conversationId, String? lastReadAt) {
    // All row badges share the same in-flight Future and therefore the same
    // single database round trip.
    return _unreadCountsFuture.then((counts) => counts[conversationId] ?? 0);
  }

  @override
  void didUpdateWidget(covariant _ConversationsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversations != widget.conversations ||
        oldWidget.currentUid != widget.currentUid) {
      _unreadCountsFuture = _fetchUnreadCounts();
      _profilesFuture = _fetchOtherParticipantProfiles();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<Map<String, Map<String, dynamic>>> _fetchOtherParticipantProfiles() async {
    final otherUids = widget.conversations.map((conv) {
      final bool iAmA = conv['participantA'] == widget.currentUid;
      return (iAmA ? conv['participantB'] : conv['participantA']) as String;
    }).toSet().toList();

    if (otherUids.isEmpty) return {};

    final rows = await Supabase.instance.client
        .from('public_profiles')
        .select()
        .inFilter('uid', otherUids);

    return {for (final p in rows) p['uid'] as String: p};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: _profilesFuture,
      builder: (context, profilesSnapshot) {
        final profiles = profilesSnapshot.data ?? const {};

        return ListView.builder(
          itemCount: widget.conversations.length,
          itemBuilder: (context, index) {
            final conv = widget.conversations[index];
            final bool iAmA = conv['participantA'] == widget.currentUid;
            final String otherUid = iAmA ? conv['participantB'] : conv['participantA'];

            final profile = profiles[otherUid];
            final userName = profile?['userName'] ?? 'User';
            final profileUrl = profile?['profileUrl'] ?? '';

            final lastReadAtRaw = iAmA ? conv['lastReadAtA'] : conv['lastReadAtB'];
            final unreadCountFuture = _unreadCountFuture(
              conv['id'].toString(),
              lastReadAtRaw?.toString(),
            );

            if (widget.query.isNotEmpty && !userName.toString().toLowerCase().contains(widget.query)) {
              return const SizedBox.shrink();
            }

            return ListTile(
                onTap: widget.isForwardMode
                    ? () => _forwardTo(
                          context,
                          otherUid: otherUid,
                          otherUserName: userName,
                          forwardText: widget.forwardText,
                          forwardImageUrl: widget.forwardImageUrl,
                          forwardImageUrls: widget.forwardImageUrls,
                        )
                    : () => _openChat(context, otherUid, userName, onReturn: widget.onChatReturn),
                onLongPress: widget.isForwardMode
                    ? null
                    : () => _deleteChatFromList(context, otherUid, userName, widget.onChatReturn),
                leading: GestureDetector(
                  onTap: widget.isForwardMode ? null : () => _openProfile(context, otherUid),
                  child: ClipOval(
                    child: GlobalCachedImage(
                      imageUrl: profileUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorWidget: const Icon(Icons.person),
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(userName, overflow: TextOverflow.ellipsis),
                    ),
                    if (!widget.isForwardMode)
                      FutureBuilder<int?>(
                        future: unreadCountFuture,
                        builder: (context, unreadSnapshot) {
                          if (unreadSnapshot.connectionState == ConnectionState.waiting) {
                            return const SizedBox.shrink();
                          }
                          if (unreadSnapshot.hasError || unreadSnapshot.data == null) {
                            return const Tooltip(
                              message: 'Unread count could not be loaded',
                              child: Icon(Icons.error_outline, size: 16, color: AppColors.error),
                            );
                          }
                          final count = unreadSnapshot.data!;
                          if (count <= 0) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(left: 8),
                            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              count > 99 ? '99+' : count.toString(),
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                  ],
                ),
            );
          },
        );
      },
    );
  }
}

class _FollowedUsersList extends StatelessWidget {
  final String currentUid;
  final String query;
  final String? forwardText;
  final String? forwardImageUrl;
  final List<String>? forwardImageUrls;

  const _FollowedUsersList({
    required this.currentUid,
    required this.query,
    this.forwardText,
    this.forwardImageUrl,
    this.forwardImageUrls,
  });

  bool get isForwardMode => forwardText != null || forwardImageUrl != null || forwardImageUrls != null;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client.from(kUsersCollection).select('following').eq('uid', currentUid).maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final following = (snapshot.data?['following'] as List?)?.cast<String>() ?? [];
        if (following.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text("Follow people to start messaging them.", textAlign: TextAlign.center),
            ),
          );
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: Supabase.instance.client.from('public_profiles').select().inFilter('uid', following),
          builder: (context, usersSnapshot) {
            final users = usersSnapshot.data ?? [];
            final filtered = query.isEmpty
                ? users
                : users.where((u) => (u['userName'] ?? '').toString().toLowerCase().contains(query)).toList();

            if (filtered.isEmpty) {
              return const Center(child: Text("No results."));
            }

            return ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final u = filtered[index];
                final userName = u['userName'] ?? 'User';
                final profileUrl = u['profileUrl'] ?? '';
                final otherUid = u['uid'] as String;

                return ListTile(
                  onTap: isForwardMode
                      ? () => _forwardTo(
                            context,
                            otherUid: otherUid,
                            otherUserName: userName,
                            forwardText: forwardText,
                            forwardImageUrl: forwardImageUrl,
                            forwardImageUrls: forwardImageUrls,
                          )
                      : () => _openChat(context, otherUid, userName),
                  leading: GestureDetector(
                    onTap: isForwardMode ? null : () => _openProfile(context, otherUid),
                    child: ClipOval(
                      child: GlobalCachedImage(
                        imageUrl: profileUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: const Icon(Icons.person),
                      ),
                    ),
                  ),
                  title: Text(userName),
                );
              },
            );
          },
        );
      },
    );
  }
}
