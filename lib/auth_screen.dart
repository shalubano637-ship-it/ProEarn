
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'models.dart';
import 'service.dart';
import 'navigation_shell.dart';
import 'chest_timer_service.dart';
import 'dart:async';
import 'theme/theme.dart';
import 'legal_text.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late Animation<double> opacityAnimation;
  String splashText = "PROMPT";

  @override
  void initState() {
    super.initState(); // Sahi tareeqa super call karne ka
    
    _checkUserDocument();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    opacityAnimation = Tween<double>(begin: 0, end: 1).animate(controller);
    controller.forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          splashText = "PRO EARN";
        });
      }
    });

    Future.delayed(const Duration(seconds: 4), () async {
      if (mounted) {
        final user = Supabase.instance.client.auth.currentUser;

        if (user != null && user.emailConfirmedAt != null) {
          final termsOk = await _ensureCurrentTermsAccepted(user.id);
          if (!mounted) return;
          if (!termsOk) {
            await Supabase.instance.client.auth.signOut();
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            );
            return;
          }

          final banned = await isCurrentUserBanned();
          if (!mounted) return;
          if (banned) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage(bannedMessage: true)),
            );
            return;
          }

           OneSignal.login(user.id); 
          ensureUserDocumentExists();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
        }
      }
    });
  }

  Future<bool> _ensureCurrentTermsAccepted(String uid) async {
    final row = await Supabase.instance.client
        .from(kUsersCollection)
        .select('termsAcceptedAt,termsVersion')
        .eq('uid', uid)
        .maybeSingle();

    if (row != null &&
        row['termsAcceptedAt'] != null &&
        row['termsVersion'] == kCurrentTermsVersion) {
      return true;
    }

    if (!mounted) return false;
    var accepted = false;
    accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Updated Terms & Safety Rules'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: SingleChildScrollView(
                  child: Text(
                    '$kTermsAndConditionsText\n\n$kCommunityGuidelinesText\n\n$kChildSafetyStandardsText',
                    style: const TextStyle(height: 1.45),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Sign out'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Agree & Continue'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!accepted) return false;

    await Supabase.instance.client
        .from(kUsersCollection)
        .update({
          'termsAcceptedAt': DateTime.now().toUtc().toIso8601String(),
          'termsVersion': kCurrentTermsVersion,
        })
        .eq('uid', uid);
    return true;
  }

  Future<void> _checkUserDocument() async {
    await ensureUserDocumentExists();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: opacityAnimation,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: Text(
              splashText,
              key: ValueKey(splashText),
              style: AppTextStyles.displayLarge.copyWith(
                color: theme.colorScheme.onSurface,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

      
class LoginPage extends StatefulWidget {
  final bool bannedMessage;
  const LoginPage({super.key, this.bannedMessage = false});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isLogin = true;
  bool hidePassword = true;
  bool hideConfirmPassword = true;
  bool acceptTerms = false;
  bool showTerms = false;
  bool showResetFields = false;
  bool isSendingReset = false;
  bool resetLinkSent = false;
  final TextEditingController resetEmailController = TextEditingController();
  final TextEditingController signupUsername = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.bannedMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Your account has been suspended by admin."),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 5),
          ),
        );
      });
    }
  }

  Future<void> sendResetLink() async {
    final email = resetEmailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your email!")),
      );
      return;
    }

    setState(() => isSendingReset = true);

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
    } catch (e) {
    }

    if (!mounted) return;
    setState(() {
      isSendingReset = false;
      resetLinkSent = true;
    });
  }

  Future<void> handleAuth() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (!acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Accept Terms & Privacy Policy")),
      );
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fill all fields")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );

    if (isLogin) {
              
      try {
        AuthResponse authResponse = await Supabase.instance.client.auth
            .signInWithPassword(email: email, password: password);

        final signedInUser = authResponse.user;
        if (signedInUser != null) {
          OneSignal.login(signedInUser.id);
        }

        if (mounted) Navigator.pop(context); // Close Loader

        if (signedInUser != null && signedInUser.emailConfirmedAt == null) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VerifyEmailPage(email: email, password: password),
              ),
            );
          }
        } else {
          final banned = await isCurrentUserBanned();
          if (!mounted) return;
          if (banned) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Your account has been suspended by admin."),
                backgroundColor: AppColors.error,
              ),
            );
            return;
          }

          currentUserEmail = email;
          currentUserName = email.split("@")[0];
          currentUserId = signedInUser!.id;
          chestTimerService.initialize();
          coinChestTimerService.initialize();
          loadUserDataOnStartup();

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
                );
                await PushService.togglePushNotificationStatus(true);
            
          }
        }
      } on AuthException catch (e) {
        if (mounted) Navigator.pop(context); // Close Loader

        String errorMessage = "Login Failed: ${e.message}";

        if (e.message.toLowerCase().contains('email not confirmed')) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VerifyEmailPage(email: email, password: password),
              ),
            );
          }
          return;
        } else if (e.message.toLowerCase().contains('invalid login credentials')) {
          errorMessage = "Incorrect email or password. Please try again.";
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: AppColors.error),
          );
        }
      } catch (e) {
        if (mounted) Navigator.pop(context); // Close Loader
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: ${e.toString()}")),
          );
        }
      }
    } else {
      final signupUsername = usernameController.text.trim();
      if (signupUsername.isEmpty) {
        if (mounted) Navigator.pop(context); // Close Loader
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please enter a username")),
          );
        }
        return;
      }
      
      if (password != confirmPasswordController.text) {
        if (mounted) Navigator.pop(context); // Close Loader
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Passwords do not match")),
          );
        }
        return;
      }

      try {
        AuthResponse authResponse = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {
            'userName': signupUsername,
            'termsAcceptedAt': DateTime.now().toUtc().toIso8601String(),
            'termsVersion': kCurrentTermsVersion,
          },
        );

        if (authResponse.user != null) {
          debugPrint("Signed up — user row will be created by the DB trigger.");
        }

        if (mounted) Navigator.pop(context); // Close Loader

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailPage(
                email: email,
                password: password,
              ),
            ),
          );
        }
      } on AuthException catch (e) {
        if (mounted) Navigator.pop(context); // Close Loader
        String errorMessage = "Signup Failed: ${e.message}";
        if (e.message.toLowerCase().contains('already registered') ||
            e.message.toLowerCase().contains('user already exists')) {
          errorMessage = "This email is already registered. Please Login.";
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: AppColors.error),
          );
        }
      } catch (e) {
        if (mounted) Navigator.pop(context); // Close Loader
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Signup Failed: ${e.toString()}")),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("PRO EARN", style: AppTextStyles.displayLarge.copyWith(color: theme.colorScheme.onSurface, letterSpacing: 2)),
                const SizedBox(height: 10),
                Text(isLogin ? "Login to continue" : "Create new account"),
                const SizedBox(height: 40),
                if (!isLogin) ...[
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(hintText: "Username"),
                  ),
                  const SizedBox(height: 20),
                ],
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(hintText: "Email"),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordController,
                  obscureText: hidePassword,
                  decoration: InputDecoration(
                    hintText: "Password",
                    suffixIcon: IconButton(
                      onPressed: () { setState(() { hidePassword = !hidePassword; }); },
                      icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
                      tooltip: hidePassword ? "Show password" : "Hide password",
                    ),
                  ),
                ),
                   
                if (isLogin) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          showResetFields = !showResetFields;
                          resetLinkSent = false;
                          isSendingReset = false;
                          resetEmailController.clear();
                        });
                      },
                      child: Text(
                        showResetFields ? "Cancel Reset" : "Forgot/Reset Password?",
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accent),
                      ),
                    ),
                  ),
                  if (showResetFields) ...[
                    const SizedBox(height: 15),
                    TextField(
                      controller: resetEmailController,
                      enabled: !resetLinkSent,
                      decoration: InputDecoration(
                        hintText: "Enter your email",
                        suffixIcon: isSendingReset
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                ))
                            : resetLinkSent
                                ? const Icon(Icons.check_circle, color: AppColors.success)
                                : null,
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (resetLinkSent)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                          borderRadius: AppRadius.mdRadius,
                        ),
                        child: Text(
                          "If that email is registered, a password reset link has been sent to it.",
                          style: AppTextStyles.bodyMedium,
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                          ),
                          onPressed: isSendingReset ? null : sendResetLink,
                          child: const Text("SEND RESET LINK", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ],
                if (!isLogin) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: hideConfirmPassword,
                    decoration: InputDecoration(
                      hintText: "Confirm Password",
                      suffixIcon: IconButton(
                        onPressed: () { setState(() { hideConfirmPassword = !hideConfirmPassword; }); },
                        icon: Icon(hideConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        tooltip: hideConfirmPassword ? "Show password" : "Hide password",
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: AppRadius.lgRadius),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: acceptTerms,
                            onChanged: (v) { setState(() { acceptTerms = v!; }); },
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                const Text("I agree to Terms & Conditions and Privacy Policy"),
                                const SizedBox(height: 12),
                                GestureDetector(
                                  onTap: () { setState(() { showTerms = !showTerms; }); },
                                  child: Row(
                                    children: [
                                      const Text("Terms & Conditions", style: TextStyle(fontWeight: FontWeight.bold)),
                                      Icon(showTerms ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                                    ],
                                  ),
                                ),
                                

if (showTerms)
  Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated, // Background color text visibility ke liye
        borderRadius: AppRadius.smRadius,
      ),
      child: SingleChildScrollView( // Isse user text ko box ke andar scroll kar sakega
        padding: const EdgeInsets.all(12),
        child: Text(
          '$kTermsAndConditionsText\n--------------------------------------------------\n$kPrivacyPolicyText',
          style: AppTextStyles.bodyRegular.copyWith(
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),
          
),
    ),

                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary),
                    onPressed: handleAuth,
                    child: Text(isLogin ? "LOGIN" : "SIGN UP", style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () { setState(() { isLogin = !isLogin; }); },
                  child: Text(isLogin ? "New user? Create account" : "Already have account? Login"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

  
class VerifyEmailPage extends StatefulWidget {
  final String email;
  final String password;

  const VerifyEmailPage({
    super.key, 
    required this.email, 
    required this.password
  });

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> with WidgetsBindingObserver {
  bool isEmailVerified = false;
  bool canResendEmail = true;
  Timer? _timer;
  int _resendCountdown = 60;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    isEmailVerified = Supabase.instance.client.auth.currentUser?.emailConfirmedAt != null;

    if (!isEmailVerified) {

      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkEmailVerifiedStatus(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkEmailVerifiedStatus();
    }
  }

  Future<void> _checkEmailVerifiedStatus() async {
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: widget.email,
        password: widget.password,
      );

      if (response.user != null && response.user!.emailConfirmedAt != null) {
        _timer?.cancel();
        _countdownTimer?.cancel();

        if (mounted) {
          setState(() {
            isEmailVerified = true;
          });

          OneSignal.login(response.user!.id);

          await ensureUserDocumentExists();

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Verification poll: not confirmed yet ($e)");
    }
  }

  void _startResendTimer() {
    setState(() {
      canResendEmail = false;
      _resendCountdown = 60;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown == 0) {
        setState(() {
          canResendEmail = true;
        });
        _countdownTimer?.cancel();
      } else {
        setState(() {
          _resendCountdown--;
        });
      }
    });
  }

  Future<void> handleResendEmail() async {
    if (!canResendEmail) return;

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      _startResendTimer();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Verification link successfully sent to your inbox!"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString().split(']').last.trim()}"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.transparent,
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              resetLocalUserState();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              }
            },
            icon: const Icon(Icons.logout, size: 18, color: AppColors.error),
            label: const Text("Cancel", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mark_email_unread_outlined,
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  "Verify your email",
                  style: AppTextStyles.displayMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(text: "We have sent a secure authentication link to:\n"),
                        TextSpan(
                          text: widget.email,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: AppRadius.lgRadius,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          "Waiting for verification... Please click the link inside your mail application.",
                          style: AppTextStyles.labelMedium.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
  width: double.infinity,
  height: 55,
  child: ElevatedButton(
    onPressed: canResendEmail ? handleResendEmail : null,
    style: ElevatedButton.styleFrom(
      backgroundColor: canResendEmail 
          ? theme.colorScheme.primary 
          : theme.colorScheme.surfaceContainerHighest,
      foregroundColor: canResendEmail 
          ? theme.colorScheme.onPrimary 
          : theme.colorScheme.onSurface.withOpacity(0.4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
    ),
    child: Text(
      canResendEmail 
          ? "RESEND VERIFICATION LINK" 
          : "RESEND LINK IN ${_resendCountdown}s",
      style: AppTextStyles.bodyLarge.copyWith(
        fontWeight: FontWeight.bold,
        color: canResendEmail 
            ? theme.colorScheme.onPrimary 
            : AppColors.textTertiary,
      ),
    ),
  ),
),
                const SizedBox(height: 20),
                
                TextButton(
                  onPressed: () async {
                    _timer?.cancel();
                    _countdownTimer?.cancel();
                    await Supabase.instance.client.auth.signOut();
                    resetLocalUserState();
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    }
                  },
                  child: Text(
                    "Back to Login Screen",
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
