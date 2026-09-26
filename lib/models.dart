// =============================================================================
// PRO EARN — Shared data models & global in-memory app state
// -----------------------------------------------------------------------------
// Split out of main.dart. Contains:
//   - Supabase table name constants
//   - NotificationModel
//   - Global in-memory caches (current user fields, likes/comments/shares
//     maps, follow/block lists) that the rest of the app reads
//     and writes directly, exactly as it did when this lived in main.dart.
//
// Dead-code pass: removed PostModel, UserModel, CommentModel, the
// demoPosts list, and initializeCommentCounts() — all were leftovers from
// the pre-Supabase (Firebase) version of the app. Nothing ever actually
// constructed a PostModel/UserModel/CommentModel (posts/comments/users
// are read as raw Supabase Map<String, dynamic> rows everywhere in the
// current code), so demoPosts was permanently an empty list and
// initializeCommentCounts() was a no-op every time it ran. Also removed
// the unused NavigatorStateExtension.popToRoot() extension (never called).
// =============================================================================

const String kUsersCollection = 'users';

const String kPostsCollection = 'posts';

const String kNotificationsCollection = 'notifications';

const String kCommentsCollection = 'comments';

const String kCooldownsCollection = 'cooldowns';

const String kReportsCollection = 'reports';

/// Only this email sees the in-app Admin Panel (Settings → Admin Panel) and
/// is allowed (server-side, via RLS in the admin migration) to read every
/// row of `reports`, ban users, and delete reported posts. Server-side
/// enforcement lives in supabase/migrations/2026_admin_reports_panel.sql —
/// this constant only controls whether the UI entry point is shown; it is
/// NOT itself a security boundary.
const String kAdminEmail = 'shalubano637@gmail.com';

/// The `posts` table's owner-identifying column.
///
/// ⚠️ NAMING LANDMINE: despite the name, this column stores the owning
/// user's UID (e.g. `Supabase.instance.client.auth.currentUser!.id`) — NOT
/// a display name. It predates the `users`/`public_profiles` tables' own
/// (correctly-named) `userName` display-name column, and the two have
/// nothing to do with each other.
///
/// Always read/write the post-owner UID through this constant instead of
/// the literal string `'userName'`, so every call site is unambiguous and
/// a future rename only has to happen in one place. If you ever run a
/// migration that renames the live column (e.g. to `owner_uid`), update
/// ONLY the value below — every call site below picks it up automatically.
const String kPostOwnerUidField = 'userName';

Map<String, int> commentCounts = {};

String currentUserName = "";

String currentUserId = "";

String currentUserEmail = "";

String currentUserBio = "";

String currentUserBioLink = "";

String currentUserProfile = "";

bool creatorAccount = false;

List<String> followers = []; List<String> following = []; List<String> blockedUsers = [];

Map<String, int> likesMap = {};

Map<String, bool> isLikedMap = {};

Map<String, int> shareCounts = {};

/// Clears every global in-memory cache above.
///
/// Must be called right after `Supabase.instance.client.auth.signOut()` at
/// EVERY sign-out call site. Without this, if a second account signs in on
/// the same device, it would start out seeing the previous account's
/// `currentUserName`/`currentUserBio`/`followers`/`blockedUsers`/likes/etc.
/// until each value happens to get overwritten — a real data-leak-between-
/// accounts risk on shared/handed-down devices.
void resetLocalUserState() {
  currentUserName = "";
  currentUserId = "";
  currentUserEmail = "";
  currentUserBio = "";
  currentUserBioLink = "";
  currentUserProfile = "";
  creatorAccount = false;

  followers.clear();
  following.clear();
  blockedUsers.clear();

  commentCounts.clear();
  likesMap.clear();
  isLikedMap.clear();
  shareCounts.clear();
}

// ================= NOTIFICATION PAGE & MODEL LAYER =================

/// A single entry in a user's notification feed (like, comment, follow, etc.).
class NotificationModel {
  final String id;
  final String type;
  final String senderId;
  final String senderName;
  final String senderProfile;
  final String message;
  final String targetPostId;
  final DateTime timestamp;

  NotificationModel({
    required this.id,
    required this.type,
    required this.senderId,
    required this.senderName,
    required this.senderProfile,
    required this.message,
    required this.targetPostId,
    required this.timestamp,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> data) {
    return NotificationModel(
      id: data['id']?.toString() ?? '',
      type: data['type'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'User',
      senderProfile: data['senderProfile'] ?? '',
      message: data['message'] ?? '',
      targetPostId: data['targetPostId'] ?? '',
      timestamp: data['timestamp'] != null
          ? DateTime.parse(data['timestamp'].toString())
          : DateTime.now(),
    );
  }
}

// Global Static Bridge Object Mapping
class ReelsAutoTrigger {
  static String? targetPostId;
  static String? highlightCommentId;
}

