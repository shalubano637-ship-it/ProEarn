// =============================================================================
// PRO EARN — social_feed.dart (barrel file)
// -----------------------------------------------------------------------------
// This file used to contain ~3,400 lines of feed/upload/post-interaction UI
// in one file. It has now been split feature-wise into the files below —
// NO logic or UI was changed, only WHERE each class physically lives.
// Every class that used to live here is still reachable via
// `import 'social_feed.dart';` exactly as before, through these exports.
//
//   Feed & Reels        -> feed/reels_page.dart, feed/admob_reel_item.dart,
//                           feed/search_page.dart, feed/single_reel_screen.dart
//   Upload & Media       -> upload/upload_page.dart, upload/global_image_adjuster.dart
//   Post interactions    -> posts/like_button.dart, posts/share_button.dart,
//                           posts/more_options_button.dart, posts/get_prompt_button.dart
//   Comments             -> comments/comment_button.dart, comments/comment_screen.dart
//   Gifts                -> gifts/gift_button.dart (also contains the private
//                           _SendGiftSheet, which GiftButton opens)
//
// feed/reels_viewer_page.dart (ReelsViewerPage) was deleted during the
// dead-code pass below — it was never navigated to from anywhere in the
// app (no route, no Navigator.push call), so it was a fully unreachable
// widget.
//
// (Orphaned banner comment carried over verbatim from the original file's
// tail, kept here for the record — it did not correspond to any class body:
// "// ================= FIXED & UPDATED ADMIN PANEL PAGE =================")
// =============================================================================

export 'feed/reels_page.dart';
export 'feed/admob_reel_item.dart';
export 'feed/search_page.dart';
export 'feed/single_reel_screen.dart';

export 'upload/upload_page.dart';
export 'upload/global_image_adjuster.dart';

export 'posts/like_button.dart';
export 'posts/share_button.dart';
export 'posts/more_options_button.dart';
export 'posts/get_prompt_button.dart';

export 'comments/comment_button.dart';
export 'comments/comment_screen.dart';

export 'gifts/gift_button.dart';
