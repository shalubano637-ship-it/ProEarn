// =============================================================================
// PRO EARN — Settings: SecurityPage
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

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../auth_screen.dart';
import '../theme/theme.dart';
import '../posts/hidden_posts_list_screen.dart';
import '../social/blocked_users_list_screen.dart';

    class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}
class _SecurityPageState extends State<SecurityPage> {
  final TextEditingController currentPasswordController = TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  bool hideCurrentPassword = true;
  bool hideNewPassword = true;
  bool passwordMatched = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // Logged-in user ka email automatically fetch karke field me set kar rahe hain
    final currentUserEmail = Supabase.instance.client.auth.currentUser?.email;
    if (currentUserEmail != null) {
      emailController.text = currentUserEmail;
    }
  }

  // STEP 1: Current Password ko Supabase Auth se Verify karna
  Future<void> verifyCurrentPassword() async {
    final user = Supabase.instance.client.auth.currentUser;
    final password = currentPasswordController.text.trim();

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("please login")),
      );
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter current password.")),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Supabase has no reauthenticateWithCredential — re-signing in with the
      // current email/password achieves the same verification.
      await Supabase.instance.client.auth.signInWithPassword(
        email: user.email!,
        password: password,
      );

      if (!mounted) return;
      setState(() {
        passwordMatched = true;
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password successfully verified!"), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Wrong current password."), backgroundColor: AppColors.error),
      );
    }
  }

  // STEP 2: Supabase Auth me New Password update karna
  Future<void> saveNewPassword() async {
    final user = Supabase.instance.client.auth.currentUser;
    final newPassword = newPasswordController.text.trim();

    if (user == null) return;

    if (newPassword.isEmpty || newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("The new password must be at least 6 characters long.")),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (!mounted) return;
      setState(() {
        passwordMatched = false;
        isLoading = false;
        currentPasswordController.clear();
        newPasswordController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password successfully updated!"), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password update failed — please try again."), backgroundColor: AppColors.error),
      );
    }
  }

  // STEP 3: Auto-Detected Email par Reset Link bhejna
  Future<void> sendPasswordResetEmail() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email not found.")),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      if (!mounted) return;
      setState(() {
        isLoading = false;
      });

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Reset Link Sent"),
          content: Text("Password reset karne link send ($email) please check your inbox."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong — please try again."), backgroundColor: AppColors.error),
      );
    }
  }

  // ACCOUNT DELETION — required by Google Play's Account Deletion policy.
  // Reuses the same password re-verification gate as the change-password
  // flow above (passwordMatched) since this is at least as sensitive, then
  // requires typing "DELETE" to confirm before calling the delete-account
  // edge function, which removes the account and all associated data
  // server-side (see supabase/functions/delete-account for exactly what's
  // deleted). This cannot be undone, so no "soft delete"/deactivate option
  // is offered — Google's policy explicitly requires real deletion, not
  // deactivation.
  Future<void> deleteAccountFlow() async {
    if (!passwordMatched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please verify your current password first.")),
      );
      return;
    }

    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "This permanently deletes your account, posts, comments, and earnings history. This cannot be undone.",
            ),
            const SizedBox(height: 12),
            const Text("Type DELETE to confirm:"),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, confirmController.text.trim() == "DELETE"),
            child: const Text("Delete", style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() { isLoading = true; });

    try {
      await Supabase.instance.client.functions.invoke('delete-account');
      await Supabase.instance.client.auth.signOut();
      resetLocalUserState();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() { isLoading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account deletion failed — please try again."), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // LOGOUT METHOD
  Future<void> handleLogout() async {
    try {
      await Supabase.instance.client.auth.signOut();
      resetLocalUserState();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const LoginPage(), // Apne login screen widget ka naam match karein
          ),
          (Route<dynamic> route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Successfully Logged Out"), 
            backgroundColor: AppColors.info
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Something went wrong — please try again."), 
          backgroundColor: AppColors.error
        ),
      );
    }
  }

  @override
  void dispose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Please Login first")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Security Settings"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.error),
            tooltip: 'Logout Account',
            onPressed: handleLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
              children: [
              // ================= SEGMENT 1: BLOCKED USERS LIVE LIVE STATUS =================
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from(kUsersCollection)
                    .stream(primaryKey: ['uid'])
                    .eq('uid', currentUser.id),
                builder: (context, snapshot) {
                  int blockedCount = 0;
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    var userData = snapshot.data!.first;
                    List<dynamic> blockedList = userData['blockedUsers'] ?? [];
                    blockedCount = blockedList.length;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.lgRadius,
                      side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: const Icon(Icons.block, color: AppColors.error, size: 28),
                      title: const Text("Blocked Users", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: const Text("Manage your blocked accounts"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer.withOpacity(0.5),
                              borderRadius: AppRadius.mdRadius,
                            ),
                            child: Text(
                              "$blockedCount",
                              style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.error),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BlockedUsersListScreen()),
                        );
                      },
                    ),
                  );
                },
              ),

              const Divider(),
              const SizedBox(height: 15),
                
                // ================= NEW: HIDDEN POSTS LIVE STATUS =================
StreamBuilder<List<Map<String, dynamic>>>(
  stream: Supabase.instance.client
      .from(kUsersCollection)
      .stream(primaryKey: ['uid'])
      .eq('uid', currentUser.id),
  builder: (context, snapshot) {
    int hiddenCount = 0;
    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
      var userData = snapshot.data!.first;
      List<dynamic> hiddenList = userData['hiddenPosts'] ?? [];
      hiddenCount = hiddenList.length;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgRadius,
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.visibility_off, color: AppColors.warning, size: 28),
        title: const Text("Hidden Posts", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: const Text("View and unhide your hidden posts."),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.2),
                borderRadius: AppRadius.mdRadius,
              ),
              child: Text(
                "$hiddenCount",
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.warning),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HiddenPostsListScreen()),
          );
        },
      ),
    );
  },
),

              // ================= SEGMENT 2: CHANGE PASSWORD =================
              const Text("Change Password", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              // Current Password Field
              TextField(
                controller: currentPasswordController,
                obscureText: hideCurrentPassword,
                enabled: !passwordMatched,
                decoration: InputDecoration(
                  hintText: "Current Password",
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: AppRadius.lgRadius, borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        hideCurrentPassword = !hideCurrentPassword;
                      });
                    },
                    tooltip: hideCurrentPassword ? "Show password" : "Hide password",
                    icon: Icon(hideCurrentPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              
              // Verify Button
              if (!passwordMatched)
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary, 
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                    ),
                    onPressed: verifyCurrentPassword,
                    child: const Text("VERIFY CURRENT PASSWORD"),
                  ),
                ),

              // New Password Segment (Only opens if verified)
              if (passwordMatched) ...[
                const SizedBox(height: 20),
                TextField(
                  controller: newPasswordController,
                  obscureText: hideNewPassword,
                  decoration: InputDecoration(
                    hintText: "New Password",
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: AppRadius.lgRadius, borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          hideNewPassword = !hideNewPassword;
                        });
                      },
                      tooltip: hideNewPassword ? "Show password" : "Hide password",
                      icon: Icon(hideNewPassword ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success, 
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                    ),
                    onPressed: saveNewPassword,
                    child: const Text("SAVE NEW PASSWORD"),
                  ),
                ),
              ],

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 25),
                child: Divider(),
              ),

              // ================= SEGMENT 3: FORGOT PASSWORD =================
              const Text("Forgot Password?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                "Send password reset link",
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 15),
              
              // Read-only Textfield
              TextField(
                controller: emailController,
                readOnly: true,
                style: const TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: AppRadius.lgRadius, borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.verified_user_outlined, color: AppColors.success),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(color: theme.colorScheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                  ),
                  onPressed: sendPasswordResetEmail,
                  child: const Text("SEND RESET LINK EMAIL"),
                ),
              ),
              const SizedBox(height: 32),
              const Divider(color: AppColors.error),
              const SizedBox(height: 12),
              const Text(
                "Danger Zone",
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                "Permanently delete your account, posts, comments, and earnings history. This cannot be undone.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                  ),
                  onPressed: deleteAccountFlow,
                  child: const Text("DELETE ACCOUNT"),
                ),
              ),
            ],
          ),
          
          if (isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            )
        ],
      ),
      ),
    );
  }
}
