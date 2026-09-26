// =============================================================================
// PRO EARN — user_profile_features.dart (barrel file)
// -----------------------------------------------------------------------------
// This file used to contain ~3,000 lines of settings/profile/social UI in
// one file. It has now been split feature-wise into the files below — NO
// logic or UI was changed, only WHERE each class physically lives. Every
// class that used to live here is still reachable via
// `import 'user_profile_features.dart';` exactly as before, through these
// exports.
//
//   Settings       -> settings/settings_page.dart, settings/push_notification_page.dart,
//                      settings/security_page.dart, settings/help_page.dart
//   Profile        -> profile/profile_page.dart, profile/edit_profile_page.dart,
//                      profile/analytics_page.dart, profile/image_crop_page.dart
//   Social         -> social/follow_list_page.dart, social/blocked_users_list_screen.dart
//   Posts          -> posts/hidden_posts_list_screen.dart
//   Notifications  -> notifications/notification_page.dart
// =============================================================================

export 'settings/settings_page.dart';
export 'settings/push_notification_page.dart';
export 'settings/security_page.dart';
export 'settings/help_page.dart';

export 'profile/profile_page.dart';
export 'profile/edit_profile_page.dart';
export 'profile/analytics_page.dart';
export 'profile/image_crop_page.dart';

export 'social/follow_list_page.dart';
export 'social/blocked_users_list_screen.dart';

export 'posts/hidden_posts_list_screen.dart';

export 'notifications/notification_page.dart';
