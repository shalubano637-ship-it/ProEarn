

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../legal_text.dart';
import '../theme/theme.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Future<void> _contactSupport(BuildContext context) async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support.prosn@gmail.com',
      queryParameters: {
        'subject': 'Support Request / Issue Report [ProSN]',
        'body': 'Hi Support Team,\n\nUser ID / Username:\nDevice Model:\n\n[Type your issue here]'
      },
    );

    try {
      final launched = await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app found. Email support.prosn@gmail.com directly.')),
        );
      }
    } catch (e) {
      debugPrint('Could not open email app: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email. Contact support.prosn@gmail.com directly.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7, // Support, Guide, About, Terms, Privacy, Community Guidelines, Child Safety
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            'ProSN Help & Support',
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
              Tab(icon: Icon(Icons.menu_book_outlined), text: "Guide"),
              Tab(icon: Icon(Icons.info_outline), text: "About Us"),
              Tab(icon: Icon(Icons.gavel), text: "Terms"),
              Tab(icon: Icon(Icons.privacy_tip), text: "Privacy"),
              Tab(icon: Icon(Icons.groups_2_outlined), text: "Guidelines"),
              Tab(icon: Icon(Icons.child_care_outlined), text: "Child Safety"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSupportTab(context),

            _buildGuideTab(),

            _buildLegalTab(_getAboutUsText()),

            _buildLegalTab(_getTermsAndConditionsText()),

            _buildLegalTab(_getPrivacyPolicyText()),

            _buildLegalTab(kCommunityGuidelinesText),

            _buildLegalTab(kChildSafetyStandardsText),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportTab(BuildContext context) {
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
              "Need help with your account, content, messages, or app features? Contact our support team.",
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: () => _contactSupport(context),
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
                      "Email Support",
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

  Widget _buildGuideTab() {
    final sections = <Map<String, dynamic>>[
      {'title': '1. Create an Account and Sign In', 'steps': ['Open ProSN and choose Sign Up if you are new.', 'Enter the requested details and complete the verification steps shown on screen.', 'If you already have an account, choose Sign In and enter your login details.', 'If you cannot access your account, use the password recovery option on the sign-in screen.']},
      {'title': '2. Browse the Feed', 'steps': ['Tap the Feed or Reels tab in the bottom navigation bar.', 'Swipe vertically to browse more posts and videos.', 'Use the available like, share, or other action buttons on a post to interact with it.', 'Tap a creator’s name or profile picture to open their profile.']},
      {'title': '3. Set Up and Edit Your Profile', 'steps': ['Tap your profile picture in the top-left corner of the main screen.', 'Open the Edit Profile option.', 'Update the fields you want to change, such as your display name, profile photo, or bio.', 'Save your changes and return to your profile to review them.']},
      {'title': '4. Upload Content', 'steps': ['Tap the Upload button in the bottom navigation bar.', 'Choose the media type and select the image or video you want to share, when available.', 'Add a caption and review the information before posting.', 'Submit the post and wait for the app to confirm that it has been uploaded.']},
      {'title': '5. Follow Creators and Manage Privacy', 'steps': ['Open a user’s profile and tap Follow, if the option is available.', 'To change account privacy, open Settings and look for the private account option.', 'Review who can message you in the messaging or privacy settings.', 'Private-account and messaging preferences may limit who can see or contact you.']},
      {'title': '6. Send and Read Messages', 'steps': ['Tap Messages in the bottom navigation bar.', 'Open an existing conversation or select a user when that option is available.', 'Type your message and tap Send.', 'If you cannot message someone, check their messaging settings and whether either account has blocked the other.']},
      {'title': '7. Coins, Gifts, and Rewards', 'steps': ['Tap the coin balance or open the Coin Shop to review available coin options.', 'Open the Bag or Gifts area to view items available to your account.', 'Follow the on-screen instructions to claim or use a reward when eligible.', 'Review the displayed price, limits, and confirmation screen before spending coins.', 'Reward availability and limits may vary. Do not assume a reward or payment is complete until the app confirms it.']},
      {'title': '8. Leaderboard and Community Rooms', 'steps': ['Tap Leaderboard in the bottom navigation bar to view rankings.', 'Open the Rooms section to browse available community rooms.', 'Choose a room and follow the on-screen instructions to join or participate.', 'Treat other users respectfully and follow the Community Guidelines.']},
      {'title': '9. Report a Problem or Contact Support', 'steps': ['Open Settings and select Help & Support.', 'Choose the Support tab and tap Contact for any issue.', 'Explain what happened in your email and list the steps that caused the issue.', 'Include your username, app version, device model, and a screenshot if helpful. Never send your password or verification code.', 'You can also email support.prosn@gmail.com directly.']}
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('ProSN Step-by-Step Guide', style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text('Follow these instructions to learn the main features of the app. Use the steps below to find common features. Some options may be available only when you are signed in.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        ...sections.map((section) => Card(
          color: AppColors.surface,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section['title'] as String, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...(section['steps'] as List<String>).asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${entry.key + 1}. ', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accent, fontWeight: FontWeight.bold)),
                    Expanded(child: Text(entry.value, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.4))),
                  ]),
                )),
              ],
            ),
          ),
        )),
      ],
    );
  }
  Widget _buildLegalTab(String text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        text,
        style: const TextStyle(
          
            color: Color(0xDEFFFFFF),

          fontSize: 13,
          height: 1.6,
          fontFamily: null,
        ),
      ),
    );
  }

  String _getAboutUsText() {
    return '''
ABOUT ProSN
Welcome to ProSN, a social platform where people can share creative content, discover creators, connect with other users, and participate in community activities.

OUR PURPOSE
ProSN aims to make sharing and discovering content simple, accessible, and enjoyable while encouraging respectful interactions between users.

WHAT YOU CAN DO
- Browse short-form posts and videos in the feed.
- Like, share, and interact with content where these options are available.
- Visit profiles and follow creators.
- Chat with other users, subject to their messaging settings.
- Explore the leaderboard, gifts, coins, and available rewards.
- Manage your profile, privacy, and app settings.

We use secure server systems to support app features and help protect user information. Specific server or service provider names are not listed here.
''';
  }

  String _getTermsAndConditionsText() => kTermsAndConditionsText;

  String _getPrivacyPolicyText() => kPrivacyPolicyText;
}
