// =============================================================================
// PRO EARN — Admin: Reports moderation panel
// -----------------------------------------------------------------------------
// In-app screen (Settings → Admin Panel), visible only when the signed-in
// user's email matches kAdminEmail (see models.dart). That client-side
// check only hides the entry point — the real access boundary is the RLS
// policies in supabase/migrations/2026_admin_reports_panel.sql, which use
// is_admin() (checks the JWT email server-side) for every read/write this
// page performs. Even if someone reached this screen without being the
// admin, every query below would simply return nothing / fail.
//
// Shows every report with:
//   - who reported (username + profile pic)
//   - who was reported (username + profile pic)
//   - reason, source (post / chat_message / chat_settings), status, time
//   - a content preview (post thumbnail+caption, or the reported message)
// and lets the admin Ban User, Delete Post, or Dismiss.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../service.dart';
import '../theme/theme.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];
  Map<String, Map<String, dynamic>> _usersById = {};
  Map<String, Map<String, dynamic>> _postsById = {};
  Map<String, Map<String, dynamic>> _commentsById = {};

  String _filter = 'pending'; // 'pending' | 'all'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var query = _client.from(kReportsCollection).select();
      if (_filter == 'pending') {
        query = query.eq('status', 'pending');
      }
      final reports = await query.order('createdAt', ascending: false).limit(300);
      final reportList = List<Map<String, dynamic>>.from(reports);

      // Collect every user uid (reporter + reported) and post id involved,
      // then fetch each in one batched query instead of N+1 look-ups.
      final userIds = <String>{};
      final postIds = <String>{};
      final commentIds = <String>{};
      for (final r in reportList) {
        if ((r['reportedBy'] as String?)?.isNotEmpty == true) userIds.add(r['reportedBy']);
        if ((r['reportedUserId'] as String?)?.isNotEmpty == true) userIds.add(r['reportedUserId']);
        if ((r['targetPostId'] as String?)?.isNotEmpty == true) postIds.add(r['targetPostId']);
        if ((r['targetCommentId'] as String?)?.isNotEmpty == true) commentIds.add(r['targetCommentId']);
      }

      Map<String, Map<String, dynamic>> usersById = {};
      if (userIds.isNotEmpty) {
        final users = await _client
            .from(kUsersCollection)
            .select('uid, userName, profileUrl, isBanned')
            .inFilter('uid', userIds.toList());
        for (final u in List<Map<String, dynamic>>.from(users)) {
          usersById[u['uid'] as String] = u;
        }
      }

      Map<String, Map<String, dynamic>> postsById = {};
      if (postIds.isNotEmpty) {
        final posts = await _client
            .from(kPostsCollection)
            .select('id, caption, imageUrl, $kPostOwnerUidField')
            .inFilter('id', postIds.toList());
        for (final p in List<Map<String, dynamic>>.from(posts)) {
          postsById[p['id'].toString()] = p;
        }
      }

      Map<String, Map<String, dynamic>> commentsById = {};
      if (commentIds.isNotEmpty) {
        final comments = await _client
            .from(kCommentsCollection)
            .select('id, commentText, userId, postId')
            .inFilter('id', commentIds.toList());
        for (final c in List<Map<String, dynamic>>.from(comments)) {
          commentsById[c['id'].toString()] = c;
        }
      }

      if (!mounted) return;
      setState(() {
        _reports = reportList;
        _usersById = usersById;
        _postsById = postsById;
        _commentsById = commentsById;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Reports load nahi hue: $e";
        _loading = false;
      });
    }
  }

  Future<void> _markStatus(Map<String, dynamic> report, String status) async {
    try {
      await _client.from(kReportsCollection).update({'status': status}).eq('id', report['id']);
      if (!mounted) return;
      setState(() => report['status'] = status);
    } catch (e) {
      _showSnack("Update fail: $e", isError: true);
    }
  }

  Future<void> _banUser(Map<String, dynamic> report) async {
    final reportedUserId = report['reportedUserId'] as String?;
    if (reportedUserId == null || reportedUserId.isEmpty) {
      _showSnack("Ye report kisi specific user se linked nahi hai.", isError: true);
      return;
    }

    final confirmed = await _confirm(
      title: "Ban this user?",
      body: "${_displayName(reportedUserId)} ko app se ban kar diya jayega.",
    );
    if (!confirmed) return;

    try {
      await _client.from(kUsersCollection).update({'isBanned': true}).eq('uid', reportedUserId);
      await _markStatus(report, 'actioned');
      if (!mounted) return;
      setState(() {
        _usersById[reportedUserId] = {...?_usersById[reportedUserId], 'isBanned': true};
      });
      _showSnack("User banned.");
    } catch (e) {
      _showSnack("Ban fail: $e", isError: true);
    }
  }

  Future<void> _deletePost(Map<String, dynamic> report) async {
    final postId = report['targetPostId'] as String?;
    if (postId == null || postId.isEmpty) {
      _showSnack("Is report ke saath koi post attached nahi hai.", isError: true);
      return;
    }

    final confirmed = await _confirm(
      title: "Delete this post?",
      body: "Ye action permanent hai — post hamesha ke liye delete ho jayegi.",
    );
    if (!confirmed) return;

    try {
      await _client.from(kPostsCollection).delete().eq('id', postId);
      await _markStatus(report, 'actioned');
      if (!mounted) return;
      setState(() => _postsById.remove(postId));
      _showSnack("Post deleted.");
    } catch (e) {
      _showSnack("Delete fail: $e", isError: true);
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> report) async {
    final commentId = report['targetCommentId'] as String?;
    if (commentId == null || commentId.isEmpty) {
      _showSnack("Is report ke saath koi comment attached nahi hai.", isError: true);
      return;
    }

    final confirmed = await _confirm(
      title: "Delete this comment?",
      body: "Ye action permanent hai — comment hamesha ke liye delete ho jayega.",
    );
    if (!confirmed) return;

    try {
      await _client.from(kCommentsCollection).delete().eq('id', commentId);
      await _markStatus(report, 'actioned');
      if (!mounted) return;
      setState(() => _commentsById.remove(commentId));
      _showSnack("Comment deleted.");
    } catch (e) {
      _showSnack("Delete fail: $e", isError: true);
    }
  }

  Future<bool> _confirm({required String title, required String body}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Confirm", style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? AppColors.error : null),
    );
  }

  String _displayName(String? uid) {
    if (uid == null || uid.isEmpty) return "Unknown";
    return (_usersById[uid]?['userName'] as String?)?.trim().isNotEmpty == true
        ? _usersById[uid]!['userName']
        : uid.substring(0, uid.length > 6 ? 6 : uid.length);
  }

  Widget _avatar(String? uid) {
    final url = _usersById[uid]?['profileUrl'] as String?;
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.textTertiary,
      child: ClipOval(
        child: (url != null && url.isNotEmpty)
            ? GlobalCachedImage(imageUrl: url, width: 36, height: 36, fit: BoxFit.cover)
            : const Icon(Icons.person, size: 18, color: Colors.white70),
      ),
    );
  }

  Widget _personChip(String label, String? uid) {
    final banned = _usersById[uid]?['isBanned'] == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _avatar(uid),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            Text(
              _displayName(uid),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: banned ? AppColors.error : null),
            ),
          ],
        ),
        if (banned) ...[
          const SizedBox(width: 4),
          const Icon(Icons.block, size: 14, color: AppColors.error),
        ],
      ],
    );
  }

  Widget _sourceChip(String? source) {
    final label = switch (source) {
      'post' => 'Post',
      'chat_message' => 'Chat message',
      'chat_settings' => 'Chat / user',
      'comment' => 'Comment',
      _ => 'Unknown',
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: AppColors.info.withOpacity(0.15),
      side: BorderSide.none,
    );
  }

  Widget _statusChip(String? status) {
    Color color;
    switch (status) {
      case 'dismissed':
        color = AppColors.textTertiary;
        break;
      case 'actioned':
        color = AppColors.warning;
        break;
      default:
        color = AppColors.error;
    }
    return Chip(
      label: Text(status ?? 'pending', style: const TextStyle(fontSize: 11, color: Colors.white)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: color,
      side: BorderSide.none,
    );
  }

  Widget _contentPreview(Map<String, dynamic> report) {
    final source = report['source'] as String?;
    if (source == 'post') {
      final post = _postsById[report['targetPostId']];
      if (post == null) {
        return const Text("Post ab exist nahi karti (delete ho chuki hai).",
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontStyle: FontStyle.italic));
      }
      final imageUrl = post['imageUrl'] as String?;
      final caption = (post['caption'] as String?)?.trim().isNotEmpty == true ? post['caption'] : "No caption";
      return Row(
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: AppRadius.smRadius,
              child: GlobalCachedImage(imageUrl: imageUrl, width: 48, height: 48, fit: BoxFit.cover),
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
        ],
      );
    }
    if (source == 'chat_message') {
      final snapshot = report['messageSnapshot'] as String?;
      return Text(
        snapshot?.isNotEmpty == true ? "\"$snapshot\"" : "(message text unavailable)",
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
      );
    }
    if (source == 'comment') {
      final comment = _commentsById[report['targetCommentId']];
      if (comment == null) {
        return const Text("Comment ab exist nahi karti (delete ho chuki hai).",
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontStyle: FontStyle.italic));
      }
      return Text(
        "\"${comment['commentText'] ?? ''}\"",
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = _client.auth.currentUser?.email?.toLowerCase().trim();
    if (currentEmail != kAdminEmail.toLowerCase()) {
      // Belt-and-suspenders: even if this page is reached without going
      // through the gated Settings entry, don't render admin content.
      // The real enforcement is server-side RLS (is_admin()) regardless.
      return const Scaffold(body: Center(child: Text("Not authorized.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin — Reports"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text("Pending")),
                ButtonSegment(value: 'all', label: Text("All")),
              ],
              selected: {_filter},
              onSelectionChanged: (s) {
                setState(() => _filter = s.first);
                _load();
              },
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)));
    if (_reports.isEmpty) return const Center(child: Text("Koi report nahi mili."));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _reports[i];
          final createdAt = DateTime.tryParse(r['createdAt']?.toString() ?? '');
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: AppRadius.mdRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _personChip("Reported by", r['reportedBy'])),
                    const SizedBox(width: 8),
                    Expanded(child: _personChip("Against", r['reportedUserId'])),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _sourceChip(r['source'] as String?),
                    _statusChip(r['status'] as String?),
                    Chip(
                      label: Text(r['reason']?.toString() ?? 'No reason', style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide.none,
                    ),
                    if (createdAt != null)
                      Text(
                        "${createdAt.toLocal()}".split('.').first,
                        style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _contentPreview(r),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _banUser(r),
                      icon: const Icon(Icons.block, size: 16, color: AppColors.error),
                      label: const Text("Ban User", style: TextStyle(color: AppColors.error)),
                    ),
                    if (r['targetPostId'] != null && (r['targetPostId'] as String).isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _deletePost(r),
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.warning),
                        label: const Text("Delete Post", style: TextStyle(color: AppColors.warning)),
                      ),
                    if (r['targetCommentId'] != null && (r['targetCommentId'] as String).isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _deleteComment(r),
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.warning),
                        label: const Text("Delete Comment", style: TextStyle(color: AppColors.warning)),
                      ),
                    if (r['status'] != 'dismissed')
                      TextButton(
                        onPressed: () => _markStatus(r, 'dismissed'),
                        child: const Text("Dismiss"),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
