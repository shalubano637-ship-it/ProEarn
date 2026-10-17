
const String kUsersCollection = 'users';

const String kPostsCollection = 'posts';

const String kNotificationsCollection = 'notifications';

const String kCommentsCollection = 'comments';

const String kCooldownsCollection = 'cooldowns';

const String kReportsCollection = 'reports';

const String kAdminEmail = 'shalubano637@gmail.com';

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

class ReelsAutoTrigger {
  static String? targetPostId;
  static String? highlightCommentId;
}

