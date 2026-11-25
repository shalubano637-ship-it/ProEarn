import 'dart:typed_data';
import 'package:universal_io/universal_io.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloudflare_media_service.dart';
import 'fcm_service.dart';
import 'models.dart';
import 'navigation_shell.dart';
import 'service.dart';
import 'chest_timer_service.dart';
import 'theme/theme.dart';
import 'utils/friendly_error.dart';
import 'profile/image_crop_page.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _imageBytes;
  String? _imageContentType;
  String? _googlePhotoUrl;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _usernameController.text = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : (user?.email?.split('@').first ?? '');
    _googlePhotoUrl = user?.photoURL;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null) return;

      Uint8List bytes;
      String contentType;
      if (kIsWeb) {
        bytes = await image.readAsBytes();
        final lower = image.name.toLowerCase();
        contentType = lower.endsWith('.png')
            ? 'image/png'
            : lower.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';
      } else {
        // Use the same Move and Scale crop interaction as Edit Profile:
        // users can drag the picture into position and pinch to zoom.
        final File? croppedFile = await Navigator.push<File?>(
          context,
          MaterialPageRoute(
            builder: (_) => ImageCropPage(imageFile: File(image.path)),
          ),
        );
        if (croppedFile == null) return;
        bytes = await croppedFile.readAsBytes();
        contentType = 'image/png';
      }

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageContentType = contentType;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(
          error,
          fallback: "Couldn't select or crop the profile image. Please try again.",
        ))),
      );
    }
  }

  Future<void> _completeSetup() async {
    if (_saving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your sign-in session expired. Please sign in again.')),
      );
      return;
    }
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (!RegExp(r'^[A-Za-z0-9_.]{3,30}$').hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username must be 3–30 characters: letters, numbers, dots or underscores.')),
      );
      return;
    }
    if (password.length < 8 || password.length > 128) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be 8–128 characters.')),
      );
      return;
    }
    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final duplicate = await Supabase.instance.client
          .from(kUsersCollection)
          .select('uid')
          .ilike('userName', username)
          .neq('uid', user.uid)
          .limit(1);
      if (duplicate.isNotEmpty) {
        throw StateError('That username is already taken. Choose another one.');
      }

      await user.reload();
      final activeUser = FirebaseAuth.instance.currentUser ?? user;
      final hasPasswordProvider = activeUser.providerData.any(
        (provider) => provider.providerId == 'password',
      );
      if (!hasPasswordProvider) {
        final credential = EmailAuthProvider.credential(
          email: activeUser.email!,
          password: password,
        );
        try {
          await activeUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (error) {
          if (error.code != 'provider-already-linked') rethrow;
        }
      }

      var profileUrl = _googlePhotoUrl ?? '';
      if (_imageBytes != null) {
        profileUrl = await CloudflareMediaService.uploadImageBytes(
          _imageBytes!,
          folder: 'profile',
          contentType: _imageContentType ?? 'image/jpeg',
        );
      }

      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null) throw StateError('Your sign-in session expired.');
      await refreshedUser.updateDisplayName(username);
      if (profileUrl.isNotEmpty) await refreshedUser.updatePhotoURL(profileUrl);

      final saved = await Supabase.instance.client
          .from(kUsersCollection)
          .update({
            'userName': username,
            'fullName': username,
            'profileUrl': profileUrl,
            'profileSetupCompleted': true,
          })
          .eq('uid', refreshedUser.uid)
          .select('uid')
          .maybeSingle();
      if (saved == null) throw StateError('Profile could not be saved. Please retry.');

      currentUserId = refreshedUser.uid;
      currentUserEmail = refreshedUser.email ?? '';
      currentUserName = username;
      currentUserProfile = profileUrl;
      await loadUserDataOnStartup();
      chestTimerService.initialize();
      await FcmService.enableForCurrentUser();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(
            error,
            fallback: 'Profile setup failed. Please try again.',
          )),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    // Give each concrete provider an explicit target type. A conditional
    // combining MemoryImage and NetworkImage can infer Object? under analyzer
    // instead of the ImageProvider<Object> required by CircleAvatar.
    ImageProvider<Object>? previewImage;
    if (_imageBytes != null) {
      previewImage = MemoryImage(_imageBytes!);
    } else if (_googlePhotoUrl != null && _googlePhotoUrl!.isNotEmpty) {
      previewImage = NetworkImage(_googlePhotoUrl!);
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Set up your ProSN profile'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'One last step',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.displayMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: GestureDetector(
                        onTap: _saving ? null : _pickProfileImage,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 62,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              backgroundImage: previewImage,
                              child: previewImage == null
                                  ? Icon(Icons.person, size: 58, color: theme.colorScheme.onSurfaceVariant)
                                  : null,
                            ),
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: theme.colorScheme.primary,
                              child: Icon(Icons.camera_alt, size: 19, color: theme.colorScheme.onPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _saving ? null : _pickProfileImage,
                      child: Text(_imageBytes == null ? 'Add profile photo (optional)' : 'Change profile photo'),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _usernameController,
                      enabled: !_saving,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'e.g. your_username',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      enabled: !_saving,
                      obscureText: _hidePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Create password',
                        helperText: 'At least 8 characters. Use it for email/password login.',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      enabled: !_saving,
                      obscureText: _hideConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hideConfirmPassword = !_hideConfirmPassword),
                          icon: Icon(_hideConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _saving ? null : _completeSetup,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Complete setup'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: user?.email ?? '',
                      readOnly: true,
                      enableInteractiveSelection: false,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        suffixIcon: user?.emailVerified == true
                            ? const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Verified',
                                      style: TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Icon(
                                      Icons.verified,
                                      color: AppColors.success,
                                      size: 21,
                                    ),
                                  ],
                                ),
                              )
                            : const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: Text(
                                  'Not verified',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
