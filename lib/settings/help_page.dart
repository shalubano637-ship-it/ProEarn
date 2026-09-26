// =============================================================================
// PRO EARN — Settings: HelpPage
// -----------------------------------------------------------------------------
// Extracted from the original user_profile_features.dart during the
// feature-based file split (no UI or logic changes — only where this code
// physically lives). user_profile_features.dart is now a barrel file that
// re-exports this file.
// =============================================================================

// =============================================================================
// PRO EARN — AI-generated content social platform
// -----------------------------------------------------------------------------
// This file (user_profile_features.dart) is one of three files this app's
// UI/logic was split into (equal three-way split of the original
// single-file main.dart, no UI or logic changes — only where each class
// physically lives):
//   1. main.dart
//   2. social_feed.dart
//   3. user_profile_features.dart  (this file)
//
// user_profile_features.dart contains everything about the user's own
// account, profile, and account-management screens:
//   - Profile & social graph: ProfilePage, FollowListPage,
//     BlockedUsersListScreen, EditProfilePage, ImageCropPage
//   - Notifications: NotificationPage, PushNotificationPage
//   - Settings & Security: SettingsPage, SecurityPage, HelpPage
//   - Analytics: AnalyticsPage
//
// Persistence: Supabase (Postgres) is the source of truth for all
// user/post/social data.
// =============================================================================

// ---- Dart core ----
import 'dart:async';

// ---- Flutter framework ----
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../legal_text.dart';
import '../theme/theme.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  // Mail app open karne ka function
  Future<void> _contactSupport() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'proearn.in@gmail.com',
      queryParameters: {
        'subject': 'Support Request / Issue Report [PRO EARN]',
        'body': 'Hi Support Team,\n\nUser ID / Username:\nDevice Model:\n\n[Type your issue here]'
      },
    );

    try {
      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch email app';
      }
    } catch (e) {
      debugPrint("Error launching email: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, // Four tabs: Support, About Us, Terms, Privacy Policy
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            'PRO EARN Support',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.background,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          elevation: 0,
          bottom: const TabBar(
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.accent,
            isScrollable: true, // Swiping controls handle multiple tabs properly
            tabs: [
              Tab(icon: Icon(Icons.support_agent), text: "Support"),
              Tab(icon: Icon(Icons.info_outline), text: "About Us"),
              Tab(icon: Icon(Icons.gavel), text: "Terms"),
              Tab(icon: Icon(Icons.privacy_tip), text: "Privacy"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ================= TAB 1: SUPPORT VIEW =================
            _buildSupportTab(),

            // ================= TAB 2: ABOUT US =================
            _buildLegalTab(_getAboutUsText()),

            // ================= TAB 3: TERMS & CONDITIONS =================
            _buildLegalTab(_getTermsAndConditionsText()),

            // ================= TAB 4: PRIVACY POLICY =================
            _buildLegalTab(_getPrivacyPolicyText()),
          ],
        ),
      ),
    );
  }

  // Support Tab Widget
  Widget _buildSupportTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.contact_support_outlined,
              size: 80,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 24),
            Text(
              "Facing any problems or have questions?",
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: _contactSupport,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: AppRadius.pillRadius,
                  boxShadow: AppElevation.accentGlow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.email_outlined, color: AppColors.textOnAccent),
                    SizedBox(width: 10),
                    Text(
                      "Contact for any issue",
                      style: TextStyle(
                        color: AppColors.textOnAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
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

  // Legal Text Scrollable Container Widget
  Widget _buildLegalTab(String text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        text,
        style: const TextStyle(
          
            color: Color(0xDEFFFFFF),

          fontSize: 13,
          height: 1.6,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  // ================= ABOUT US CONTENT =================
  String _getAboutUsText() {
    return '''
ABOUT PRO EARN
Welcome to PRO EARN, the premier social environment designed specifically for AI-generated media creators and tech enthusiasts.

OUR MISSION
Our core objective is to empower prompt engineers, digital creative minds, and social media enthusiasts by providing an engaging framework where AI creativity directly maps to economic incentives. We bridge the gap between algorithmic processing and active audience validation.

WHAT WE DO
- Provide an advanced 9:16 vertical feed ecosystem optimized for rich UI presentation.
- Implement an absolute validation architecture ('Gets' scoring mechanics) that calculates content performance metrics in real-time.
- Foster a safe, heavily moderated social space that champions original generation setups while maintaining strict adherence to universal app marketplace policy guidelines.

Powered by secure infrastructure pipelines and automated cloud classification algorithms, PRO EARN delivers a next-generation decentralized engagement environment.
''';
  }

  // ================= TERMS AND CONDITIONS CONTENT =================
  // Sourced from legal_text.dart — was previously duplicated inline here
  // and had drifted out of sync with the auth_screen.dart copy.
  String _getTermsAndConditionsText() => kTermsAndConditionsText;

  // ================= PRIVACY POLICY CONTENT =================
  // Sourced from legal_text.dart — was previously duplicated inline here
  // and had drifted out of sync with the auth_screen.dart copy (this copy
  // still said "Google Firebase Authentication and Firestore DB" from
  // before the Supabase migration).
  String _getPrivacyPolicyText() => kPrivacyPolicyText;
}
