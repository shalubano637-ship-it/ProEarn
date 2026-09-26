// =============================================================================
// PRO EARN — Comments: CommentScreen
// -----------------------------------------------------------------------------
// Extracted from the original social_feed.dart during the feature-based
// file split (no UI or logic changes — only where this code physically
// lives). social_feed.dart is now a barrel file that re-exports this file.
// =============================================================================

// =============================================================================
// PRO EARN — AI-generated content social platform
// -----------------------------------------------------------------------------
// This file (social_feed.dart) is one of three files this app's UI/logic
// was split into (equal three-way split of the original single-file
// main.dart, no UI or logic changes — only where each class physically
// lives):
//   1. main.dart
//   2. social_feed.dart            (this file)
//   3. user_profile_features.dart
//
// social_feed.dart contains everything about browsing, creating, and
// interacting with posts/reels:
//   - Feed & Reels: ReelsPage, SearchPage, SingleReelScreen
//   - Upload & Media: UploadPage, GlobalImageAdjuster
//   - Post interactions: LikeButton, CommentButton, CommentScreen,
//     ShareButton, MoreOptionsButton, GetPromptButton (creator earnings)
//
// Persistence: Supabase (Postgres) is the source of truth for all
// user/post/social data.
// =============================================================================

// ---- Dart core ----
import 'dart:async';
import 'dart:io';

// ---- Flutter framework ----
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- Third-party packages ----
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../service.dart';
import '../user_profile_features.dart';
import '../theme/theme.dart';
import '../utils.dart';
// Images/gifts in comments reuse the exact same picker/compress/moderate/
// upload pipeline chat already has — same UI, same behavior, on purpose
// (that's what was asked for), just posting into `comments` instead of
// calling send_message.
import '../messaging/chat_image_preview_page.dart';
import '../messaging/chat_multi_image_preview_page.dart';
import 'comment_gift_sheet.dart';



  class CommentScreen extends StatefulWidget {
  final String postId;
  final String? highlightCommentId; 

  const CommentScreen({super.key, required this.postId, this.highlightCommentId});

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}
// Same trick as chat's _groupConsecutiveImages: a gallery multi-send posts
// several image-only comments back-to-back (same sender, no text, not a
// reply), so this clusters adjacent ones from the stream into one album
// tile — no new column/table needed. Only applied to TOP-LEVEL comments
// (not replies), since a multi-photo reply is a rare enough case to skip
// for now.
List<List<Map<String, dynamic>>> _groupConsecutiveImageComments(List<Map<String, dynamic>> comments) {
  bool isPlainImage(Map<String, dynamic> c) =>
      (c['imageUrl'] as String?)?.isNotEmpty == true &&
      ((c['commentText'] ?? '') as String).isEmpty &&
      (c['parentCommentId'] == null || c['parentCommentId'].toString().isEmpty);

  final groups = <List<Map<String, dynamic>>>[];
  for (final c in comments) {
    if (groups.isNotEmpty && isPlainImage(c)) {
      final lastGroup = groups.last;
      final lastC = lastGroup.last;
      final sameSender = lastC['userId'] == c['userId'];
      final closeInTime = DateTime.parse(c['timestamp'].toString())
          .difference(DateTime.parse(lastC['timestamp'].toString()))
          .abs() <= const Duration(seconds: 10);
      if (isPlainImage(lastC) && sameSender && closeInTime) {
        lastGroup.add(c);
        continue;
      }
    }
    groups.add([c]);
  }
  return groups;
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  String? _currentlyHighlightedId;

  // Track reply context
  String? _replyingToUserId;
  String? _replyingToUsername;
  String? _replyingToCommentId; // This acts as parentCommentId
  String? _editingCommentId; // non-null while the input bar is editing an existing comment instead of posting a new one

  // Track which comment threads are expanded (unfolded)
  final Set<String> _expandedCommentIds = {};

    // 🔥 Stream Cache Map
  final Map<String, Future<Map<String, dynamic>?>> _userProfileCache = {};

  // Cached per-uid profile fetch for comment/reply authors — was a Stream
  // cache pointed at the full `users` table. Comment author name/avatar
  // doesn't need to be live, and Supabase Realtime doesn't fire on views
  // anyway, so this is now a one-time Future cache against public_profiles
  // (no email/upiId/address exposure, same de-dup-by-uid benefit as before).
  Future<Map<String, dynamic>?> _getUserProfile(String uid) {
    if (uid.isEmpty) {
      return Future.value(null);
    }

    if (!_userProfileCache.containsKey(uid)) {
      _userProfileCache[uid] = Supabase.instance.client
          .from('public_profiles')
          .select()
          .eq('uid', uid)
          .maybeSingle();
    }
    return _userProfileCache[uid]!;
  }

    
  String? _postOwnerId; // fetched once — decides who sees Delete/Report on someone ELSE's comment

  @override
  void initState() {
    super.initState();
    _currentlyHighlightedId = widget.highlightCommentId;
    
    if (_currentlyHighlightedId != null && _currentlyHighlightedId!.isNotEmpty) {
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _currentlyHighlightedId = null;
          });
        }
      });
    }

    Supabase.instance.client
        .from(kPostsCollection)
        .select(kPostOwnerUidField)
        .eq('id', widget.postId)
        .maybeSingle()
        .then((row) {
      if (mounted) setState(() { _postOwnerId = row?[kPostOwnerUidField] as String?; });
    }).catchError((e) => debugPrint("Couldn't load post owner for comment permissions: $e"));
  }

  @override
  void dispose() {
    _commentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  
      void _navigateToProfile(String commentUid) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null || commentUid.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          isOwnProfile: commentUid == currentUser.id,
          otherUser: commentUid,
        ),
      ),
    );
  }

    
  static const List<String> _commentReportReasons = [
    "Spam or Misleading",
    "Hate Speech or Violence",
    "Harassment or Bullying",
    "Nudity or Sexual Content",
    "Intellectual Property Violation",
  ];

  // Long-press menu for a comment/reply — options shown depend on who's
  // looking:
  //   - Wrote it themselves: Reply, Edit, Delete (no Report — can't
  //     report your own comment).
  //   - Owns the POST (but didn't write this comment): Reply, Report,
  //     Delete (moderation — can remove any comment on their own post).
  //   - Anyone else: Reply, Report.
  void _showCommentOptions({
    required String commentId,
    required String commentUid,
    required String commentUsername,
    required String commentText,
    bool isImage = false,
  }) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    final bool isAuthor = myUid != null && myUid == commentUid;
    final bool isPostOwner = myUid != null && myUid == _postOwnerId;

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
                _startReply(commentUid, commentUsername, commentId);
              },
            ),
            if (isAuthor && !isImage) // nothing text-based to edit on a photo/gift comment
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("Edit"),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editComment(commentId, commentText);
                },
              ),
            if (!isAuthor)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.error),
                title: const Text("Report", style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reportComment(commentId, commentUid);
                },
              ),
            if (isAuthor || isPostOwner)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text("Delete", style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteComment(commentId, isAuthor: isAuthor);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Edit happens INLINE in the same input box used for posting/replying
  // (not a popup) — this just switches the bar into "editing" mode; see
  // _postComment for where the save actually happens, and the "Editing
  // comment" chip in the input bar for the cancel (X) button.
  void _editComment(String commentId, String currentText) {
    setState(() {
      _editingCommentId = commentId;
      _replyingToUserId = null;
      _replyingToUsername = null;
      _replyingToCommentId = null;
    });
    _commentController.text = currentText;
    _focusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() { _editingCommentId = null; });
    _commentController.clear();
    _focusNode.unfocus();
  }

  Future<void> _deleteComment(String commentId, {required bool isAuthor}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete this comment?"),
        content: const Text("This can't be undone. Any replies to it will be removed too."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete", style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (isAuthor) {
        await Supabase.instance.client.rpc('delete_own_comment', params: {'p_comment_id': commentId});
      } else {
        // Not the author — this must be the post owner moderating a
        // comment on their own post, which needs elevated privilege
        // (normal RLS wouldn't let you delete someone else's row).
        await Supabase.instance.client.rpc('delete_comment_as_post_owner', params: {
          'p_comment_id': commentId,
          'p_post_id': widget.postId,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't delete — please try again."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _reportComment(String commentId, String commentOwnerId) {
    String? selectedReason;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset > 0 ? bottomInset + 24 : 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Report this comment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    hint: const Text("Select a reason"),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: AppRadius.smRadius, borderSide: BorderSide.none),
                    ),
                    items: _commentReportReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (v) => setSheetState(() { selectedReason = v; }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: selectedReason == null ? null : () async {
                        Navigator.pop(sheetContext);
                        try {
                          await Supabase.instance.client.from(kReportsCollection).insert({
                            'reportedBy': Supabase.instance.client.auth.currentUser!.id,
                            'reportedUserId': commentOwnerId,
                            'targetCommentId': commentId,
                            'reason': selectedReason,
                            'source': 'comment',
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
                      child: const Text("SUBMIT REPORT"),
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

  void _viewCommentImageFullscreen(String imageUrl) {
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

  void _startReply(String userId, String username, String commentId) {
    setState(() {
      _replyingToUserId = userId;
      _replyingToUsername = username;
      _replyingToCommentId = commentId;
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToUserId = null;
      _replyingToUsername = null;
      _replyingToCommentId = null;
    });
    _commentController.clear();
    _focusNode.unfocus();
  }

  // Camera / single gallery photo — same compress+moderate+upload pipeline
  // as chat (chat_image_preview_page.dart), just posted as a comment
  // instead of a chat message. Replies-to-a-comment can carry a photo
  // too (parentId/replyTo carry over same as a text reply).
  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null || !mounted) return;
      final url = await showChatImagePreview(context, File(picked.path));
      if (url != null) await _postImageComment(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open camera/gallery."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // Gallery multi-select (up to 20) — same album trick chat uses: post
  // several image-only comments back-to-back, close together in time,
  // and the rendering side (_groupConsecutiveComments) re-groups them
  // into one tile automatically.
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
        await _postImageComment(url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open gallery."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _postImageComment(String imageUrl) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final repliedUserId = _replyingToUserId;
    final parentId = _replyingToCommentId;
    final replyUsername = _replyingToUsername;
    if (_replyingToUsername != null) _cancelReply();

    try {
      await Supabase.instance.client.from(kCommentsCollection).insert({
        'postId': widget.postId,
        'userId': currentUser.id,
        'commentText': '',
        'imageUrl': imageUrl,
        'replyToUserId': repliedUserId,
        'replyToUsername': replyUsername,
        'parentCommentId': parentId,
      });
      if (parentId != null) setState(() { _expandedCommentIds.add(parentId); });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't post photo — please try again."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    // Editing an existing comment — save and stop here, don't fall
    // through to posting a brand new one.
    if (_editingCommentId != null) {
      final commentId = _editingCommentId!;
      _cancelEdit();
      try {
        await Supabase.instance.client.rpc('edit_comment', params: {
          'p_comment_id': commentId,
          'p_new_text': text,
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't save edit — please try again."), backgroundColor: AppColors.error),
          );
        }
      }
      return;
    }

    String finalCommentText = text;
    String? repliedUserId = _replyingToUserId;
    String? parentId = _replyingToCommentId;
    String? replyUsername = _replyingToUsername;
    
    _cancelReply();

    try {
      // 1. Save comment in Supabase
      await Supabase.instance.client
          .from(kCommentsCollection)
          .insert({
        'postId': widget.postId,
        'userId': currentUser.id,
        'commentText': finalCommentText,
        'replyToUserId': repliedUserId,
        'replyToUsername': replyUsername,
        'parentCommentId': parentId, // Stores parent comment ID if it's a reply
      });

      // Auto expand the parent comment thread so user sees their posted reply immediately
      if (parentId != null) {
        setState(() {
          _expandedCommentIds.add(parentId);
        });
      }

      try {
        // ================= NEW NOTIFICATION LOGIC =================
        if (repliedUserId != null && repliedUserId.isNotEmpty) {
          // 1. REPLIED USER NOTIFICATION (Sirf jisko reply kiya hai usko jayega)
          if (repliedUserId != currentUser.id) {
            await sendNotification(
              targetOwnerId: repliedUserId,
              type: 'comment',
              message: 'replied to your comment',
              targetPostId: widget.postId,
            );
          }
        } else {
          // 2. POST OWNER NOTIFICATION (Normal comment hone par sirf post owner ko jayega)
          final postDoc = await Supabase.instance.client
              .from(kPostsCollection)
              .select()
              .eq('id', widget.postId)
              .maybeSingle();

          if (postDoc != null) {
            final postOwnerId = postDoc[kPostOwnerUidField] ?? '';

            if (postOwnerId.isNotEmpty && postOwnerId != currentUser.id) {
              await sendNotification(
                targetOwnerId: postOwnerId,
                type: 'comment',
                message: 'commented on your post',
                targetPostId: widget.postId,
              );
            }
          }
        }
        // =========================================================
      } catch (notificationError) {
        // The comment itself already saved successfully above — a failure
        // here is just a missed push notification, not a failed comment,
        // so this stays a silent debug log rather than a user-facing error.
        debugPrint("Comment posted but notification failed: $notificationError");
      }

    } catch (e) {
      final isModerationRejection = e is PostgrestException &&
          (e.message.contains('Content rejected') || e.code == 'P0001');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isModerationRejection
                  ? "Comment not allowed: contains blocked content."
                  : "Couldn't post comment — try again.",
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      debugPrint("Comment operation error: $e");
    }
  }

            

    

  // Format Timestamp Helper
  String _formatCommentTimestamp(dynamic timestamp) => formatRelativeTimestamp(timestamp);

  void _toggleExpandThread(String commentId) {
    setState(() {
      if (_expandedCommentIds.contains(commentId)) {
        _expandedCommentIds.remove(commentId);
      } else {
        _expandedCommentIds.add(commentId);
      }
    });
  }

  
       // Perfect Inline Layout: [Jerry_Avatar] Jerry replying to [Nasir_Avatar] @nasir hello
  Widget _buildCommentTile({
    required Map<String, dynamic> cDoc,
    required Map<String, dynamic> cData,
    required bool isDarkMode,
    required ThemeData theme,
    bool isReply = false,
  }) {
    final String commentUid = cData['userId'] ?? '';
    final String commentText = cData['commentText'] ?? '';
    final String replyToUsername = cData['replyToUsername'] ?? '';
    final String replyToUserId = cData['replyToUserId'] ?? ''; 
    final dynamic timestamp = cData['timestamp'];
    final String? imageUrl = cData['imageUrl'] as String?;
    // Gift comments (from comment_gift_sheet.dart) are tagged the same
    // way chat tags them — a "🎁 " text prefix, no separate column.
    final bool isGift = commentText.startsWith('🎁');
    final bool isImage = imageUrl != null && imageUrl.isNotEmpty;
    final bool isEdited = cData['isEdited'] == true;
    bool isThisCommentHighlighted = _currentlyHighlightedId == cDoc['id'].toString();

    return FutureBuilder<Map<String, dynamic>?>(
      future: _getUserProfile(commentUid),
      builder: (context, userSnap) {
        String name = "User";
        String profileUrl = "";
        if (userSnap.hasData && userSnap.data != null) {
          final uMap = userSnap.data!;
          name = uMap['userName'] ?? 'User';
          profileUrl = uMap['profileUrl'] ?? '';
        }

        return GestureDetector(
          onLongPress: () => _showCommentOptions(
            commentId: cDoc['id'].toString(),
            commentUid: commentUid,
            commentUsername: name,
            commentText: commentText,
            isImage: isImage, // suppresses Edit — nothing text-based to edit on a photo/gift
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.only(top: 8, bottom: 8, left: isReply ? 32.0 : 0.0),
            color: isThisCommentHighlighted 
                ? (isDarkMode ? AppColors.info.withOpacity(0.2) : AppColors.warning.withOpacity(0.3))
                : AppColors.transparent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. MAIN COMMENTER AVATAR (Jerry's Main Avatar)
                GestureDetector(
                  onTap: () => _navigateToProfile(commentUid),
                  child: CircleAvatar(
                    radius: isReply ? 14 : 18,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    backgroundImage: profileUrl.isNotEmpty ? CachedNetworkImageProvider(profileUrl, cacheManager: CustomImageCacheManager.instance) : null,
                    child: profileUrl.isEmpty ? Icon(Icons.person, size: isReply ? 14 : 18) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2. INLINE TEXT WITH INLINE REPLIED AVATAR
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            color: theme.colorScheme.onSurface, 
                            fontSize: 14,
                          ),
                          children: [
                            // Comment Creator Name (e.g., "Jerry ")
                            TextSpan(
                              text: "$name ", 
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              recognizer: TapGestureRecognizer()..onTap = () => _navigateToProfile(commentUid),
                            ),

                            // Reply Section
                            if (replyToUsername.isNotEmpty) ...[
                              const TextSpan(
                                text: "replying to ",
                                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                              ),

                              // 🔥 INLINE REPLIED USER AVATAR (Nasir's Avatar)
                              if (replyToUserId.isNotEmpty)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: FutureBuilder<Map<String, dynamic>?>(
                                    future: _getUserProfile(replyToUserId),
                                    builder: (context, repliedUserSnap) {
                                      String repliedProfileUrl = "";
                                      if (repliedUserSnap.hasData && repliedUserSnap.data != null) {
                                        repliedProfileUrl = repliedUserSnap.data!['profileUrl'] ?? '';
                                      }

                                      return GestureDetector(
                                        onTap: () => _navigateToProfile(replyToUserId),
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 4),
                                          child: CircleAvatar(
                                            radius: 9, // Small avatar
                                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                            backgroundImage: repliedProfileUrl.isNotEmpty 
                                                ? CachedNetworkImageProvider(repliedProfileUrl, cacheManager: CustomImageCacheManager.instance) 
                                                : null,
                                            child: repliedProfileUrl.isEmpty 
                                                ? const Icon(Icons.person, size: 9, color: AppColors.textTertiary) 
                                                : null,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                              // Replied Username (e.g., "@nasir ")
                              TextSpan(
                                text: "@$replyToUsername ", 
                                style: TextStyle(
                                  color: theme.colorScheme.primary, 
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    if (replyToUserId.isNotEmpty) {
                                      _navigateToProfile(replyToUserId);
                                    }
                                  },
                              ),
                            ],

                            // Actual Comment Text (empty for a photo-only comment; "🎁 Sent X" for a gift)
                            TextSpan(text: commentText),
                          ],
                        ),
                      ),
                      // Photo / gift — same visual treatment as chat:
                      // gift shows small (just a receipt), a real photo
                      // shows bigger; tap opens fullscreen, no crop.
                      if (isImage) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _viewCommentImageFullscreen(imageUrl),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: GlobalCachedImage(
                              imageUrl: imageUrl,
                              width: isGift ? 72 : 160,
                              height: isGift ? 72 : 160,
                              fit: isGift ? BoxFit.contain : BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      
                      // Timestamp & Reply Button
                      Row(
                        children: [
                          Text(
                            _formatCommentTimestamp(timestamp),
                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _startReply(commentUid, name, cDoc['id'].toString()),
                            child: const Text(
                              "Reply", 
                              style: TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (isEdited) ...[
                            const SizedBox(width: 8),
                            const Text(
                              "edited",
                              style: TextStyle(color: AppColors.textTertiary, fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

                
                              
                  

    
            
                              

                            
                      
               
       
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final keyboardPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scaffold(
        backgroundColor: AppColors.transparent,
        resizeToAvoidBottomInset: false, 
        appBar: AppBar(
          backgroundColor: AppColors.transparent,
          elevation: 0,
          title: const Text("Comments", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          centerTitle: true,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(icon: const Icon(Icons.close), tooltip: "Close", onPressed: () => Navigator.pop(context))
          ],
        ),
        body: Padding(
          padding: EdgeInsets.only(bottom: keyboardPadding),
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from(kCommentsCollection)
                      .stream(primaryKey: ['id'])
                      .eq('postId', widget.postId)
                      .order('timestamp', ascending: false),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text("No comments yet. Be the first to comment!", style: TextStyle(color: AppColors.textTertiary))
                      );
                    }

                    final allDocs = snapshot.data!;

                    // Separate main comments vs replies
                    final mainComments = allDocs.where((data) {
                      final parentId = data['parentCommentId'];
                      return parentId == null || parentId.toString().isEmpty;
                    }).toList();

                    final mainGroups = _groupConsecutiveImageComments(mainComments);

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: mainGroups.length,
                      itemBuilder: (context, index) {
                        final group = mainGroups[index];
                        final parentData = group.first;
                        final String parentId = parentData['id'].toString();

                        if (group.length > 1) {
                          // Gallery-multi-send album — grid tile, tap opens
                          // a swipeable viewer. Kept simple (no per-photo
                          // Reply/Forward/Remove menu like chat has) since
                          // these are rare in comments; long-press the tile
                          // itself still offers Delete/Report for the batch
                          // via its first photo.
                          final imageUrls = group.map((c) => c['imageUrl'] as String).toList();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: GestureDetector(
                              onLongPress: () => _showCommentOptions(
                                commentId: parentId,
                                commentUid: parentData['userId'] ?? '',
                                commentUsername: '',
                                commentText: '',
                                isImage: true,
                              ),
                              child: SizedBox(
                                width: 160,
                                height: 160,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 2, mainAxisSpacing: 2),
                                  itemCount: imageUrls.length > 4 ? 4 : imageUrls.length,
                                  itemBuilder: (context, i) {
                                    final isLastWithMore = imageUrls.length > 4 && i == 3;
                                    return GestureDetector(
                                      onTap: () => _viewCommentImageFullscreen(imageUrls[i]),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          GlobalCachedImage(imageUrl: imageUrls[i], fit: BoxFit.cover),
                                          if (isLastWithMore)
                                            Container(
                                              color: Colors.black54,
                                              child: Center(
                                                child: Text("+${imageUrls.length - 4}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        }

                        // Find child replies corresponding to this main comment
                        final childReplies = allDocs.where((data) {
                          return data['parentCommentId'] == parentId;
                        }).toList();

                        // Reverse child list so oldest replies show first in child thread
                        final sortedChildReplies = childReplies.reversed.toList();
                        bool isExpanded = _expandedCommentIds.contains(parentId);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Main Comment Tile
                            _buildCommentTile(
                              cDoc: parentData,
                              cData: parentData,
                              isDarkMode: isDarkMode,
                              theme: theme,
                              isReply: false,
                            ),

                            // Fold / Unfold Arrow Action
                            if (sortedChildReplies.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 48.0, top: 2.0, bottom: 6.0),
                                child: InkWell(
                                  onTap: () => _toggleExpandThread(parentId),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 1,
                                        color: AppColors.textTertiary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isExpanded
                                            ? "Hide replies"
                                            : "View ${sortedChildReplies.length} reply${sortedChildReplies.length > 1 ? 's' : ''}",
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        size: 18,
                                        color: AppColors.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Nested Child Replies (Displayed when expanded)
                            if (isExpanded && sortedChildReplies.isNotEmpty)
                              Column(
                                children: sortedChildReplies.map((replyData) {
                                  return _buildCommentTile(
                                    cDoc: replyData,
                                    cData: replyData,
                                    isDarkMode: isDarkMode,
                                    theme: theme,
                                    isReply: true,
                                  );
                                }).toList(),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              
              // Bottom Input Bar Area — same layout as chat_page.dart's
              // input bar on purpose (Camera | text field | Gallery |
              // Gift | Send), so comments and chat feel identical.
              // Wrapped in SafeArea (not manual MediaQuery arithmetic)
              // so the icons never sit behind a 3-button nav bar.
              SafeArea(
                top: false,
                child: Container(
                  color: theme.colorScheme.surface,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_editingCommentId != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? AppColors.surfaceElevated : AppColors.border,
                            borderRadius: AppRadius.smRadius,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Editing comment", style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                              GestureDetector(
                                onTap: _cancelEdit,
                                child: const Icon(Icons.close, size: 16, color: AppColors.textTertiary),
                              ),
                            ],
                          ),
                        )
                      else if (_replyingToUsername != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? AppColors.surfaceElevated : AppColors.border,
                            borderRadius: AppRadius.smRadius,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Replying to @$_replyingToUsername", style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                              GestureDetector(
                                onTap: _cancelReply,
                                child: const Icon(Icons.close, size: 16, color: AppColors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.camera_alt_outlined),
                            tooltip: "Camera",
                            onPressed: _editingCommentId != null ? null : () => _pickAndSendImage(ImageSource.camera),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              focusNode: _focusNode,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 4,
                              minLines: 1,
                              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: _editingCommentId != null ? "Edit your comment..." : "Add a comment...",
                                hintStyle: const TextStyle(color: AppColors.textTertiary),
                                filled: true,
                                fillColor: isDarkMode ? AppColors.surfaceHighlight : AppColors.divider,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.image_outlined),
                            tooltip: "Gallery",
                            onPressed: _editingCommentId != null ? null : _pickAndSendMultipleImages,
                          ),
                          IconButton(
                            icon: const Icon(Icons.card_giftcard_outlined),
                            tooltip: "Send a gift",
                            onPressed: _editingCommentId != null
                                ? null
                                : () => showCommentGiftSheet(context, postId: widget.postId),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send),
                            tooltip: _editingCommentId != null ? "Save" : "Post",
                            onPressed: _postComment,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
