
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models.dart';
import '../ad_unit_ids.dart';
import '../theme/theme.dart';
import '../service.dart';
import 'chat_page.dart';
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

  Future<List<Map<String, dynamic>>> _fetchConversations() {
    final currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    return Supabase.instance.client
        .from('conversations')
        .select()
        .or('participantA.eq.$currentUid,participantB.eq.$currentUid')
        .order('lastMessageAt', ascending: false);
  }

  void _refreshConversations() {
    if (mounted) setState(() { _conversationsFuture = _fetchConversations(); });
  }

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _fetchConversations();
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
    _searchController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (currentUid.isEmpty) {
      return const Scaffold(body: Center(child: Text("Please log in.")));
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.isForwardMode ? "Forward to…" : "Messages")),
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
                if (convSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (convSnapshot.hasError) {
                  return ErrorRetryView(
                    error: convSnapshot.error,
                    onRetry: () => setState(() {}),
                  );
                }
                final allConversations = convSnapshot.data ?? [];
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
              },
            ),
          ),
        ],
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

  @override
  void initState() {
    super.initState();
    _profilesFuture = _fetchOtherParticipantProfiles();
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

  Future<void> _toggleSave(String conversationId, bool currentlySaved) async {
    try {
      await Supabase.instance.client.rpc('save_conversation', params: {
        'p_conversation_id': conversationId,
        'p_saved': !currentlySaved,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(!currentlySaved ? "Chat saved — won't clear when app closes" : "Chat unsaved")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update — please try again."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _confirmDelete(String conversationId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Delete chat with $userName?"),
        content: const Text("This removes it from your list only — the other person still sees it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete", style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client.rpc('hide_conversation_for_me', params: {'p_conversation_id': conversationId});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't delete — please try again."), backgroundColor: AppColors.error),
          );
        }
      }
    }
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
            final String conversationId = conv['id'] as String;
            final bool iAmA = conv['participantA'] == widget.currentUid;
            final String otherUid = iAmA ? conv['participantB'] : conv['participantA'];
            final bool isSaved = iAmA ? (conv['savedByA'] ?? false) : (conv['savedByB'] ?? false);

            final profile = profiles[otherUid];
            final userName = profile?['userName'] ?? 'User';
            final profileUrl = profile?['profileUrl'] ?? '';

            final lastMessageAtRaw = conv['lastMessageAt'];
            final lastReadAtRaw = iAmA ? conv['lastReadAtA'] : conv['lastReadAtB'];
            final bool hasUnread = lastMessageAtRaw != null &&
                (lastReadAtRaw == null ||
                    DateTime.parse(lastMessageAtRaw.toString())
                        .isAfter(DateTime.parse(lastReadAtRaw.toString())));

            if (widget.query.isNotEmpty && !userName.toString().toLowerCase().contains(widget.query)) {
              return const SizedBox.shrink();
            }

            return GestureDetector(
              onLongPress: widget.isForwardMode ? null : () => _confirmDelete(conversationId, userName),
              child: ListTile(
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
                leading: GestureDetector(
                  onTap: widget.isForwardMode ? null : () => _openProfile(context, otherUid),
                  child: CircleAvatar(
                    backgroundColor: AppColors.border,
                    backgroundImage: profileUrl.isNotEmpty
                        ? CachedNetworkImageProvider(profileUrl, cacheManager: CustomImageCacheManager.instance)
                        : null,
                    child: profileUrl.isEmpty ? const Icon(Icons.person) : null,
                  ),
                ),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(userName, overflow: TextOverflow.ellipsis)),
                    if (hasUnread) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
                trailing: widget.isForwardMode
                    ? null
                    : IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSaved ? AppColors.accent.withOpacity(0.15) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSaved ? Icons.download_done : Icons.download_outlined,
                            color: isSaved ? AppColors.accent : AppColors.textTertiary,
                          ),
                        ),
                        tooltip: isSaved ? "Saved — won't auto-clear" : "Save this chat",
                        onPressed: () => _toggleSave(conversationId, isSaved),
                      ),
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
                    child: CircleAvatar(
                      backgroundColor: AppColors.border,
                      backgroundImage: profileUrl.isNotEmpty
                          ? CachedNetworkImageProvider(profileUrl, cacheManager: CustomImageCacheManager.instance)
                          : null,
                      child: profileUrl.isEmpty ? const Icon(Icons.person) : null,
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
