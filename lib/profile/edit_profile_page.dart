// =============================================================================
// PRO EARN — Profile: EditProfilePage
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
import 'package:universal_io/universal_io.dart';

// ---- Flutter framework ----
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---- Supabase ----
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- Third-party packages ----
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../models.dart';
import '../service.dart';
import '../moderation/moderation_config.dart';
import '../theme/theme.dart';
import 'image_crop_page.dart';

           // ================= STRUCTURAL ISOLATED CELEBRATION WIDGET (24-Hour Auto-Expire) =================
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}
class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController nameController;
  late TextEditingController bioController;
  
  

  File? _selectedProfileImage;
  final ImagePicker _profilePicker = ImagePicker();
  
  
  bool isLoadingPic = true;
  String currentCloudPicUrl = "";

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: currentUserName);
    bioController = TextEditingController(text: currentUserBio);
    


    _loadCurrentUserData();
  }

  Future<void> _loadCurrentUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        var userData = await Supabase.instance.client.from(kUsersCollection).select().eq('uid', user.id).maybeSingle();
        if (!mounted) return;
        if (userData != null) {
          var data = userData;
          setState(() {
            currentCloudPicUrl = data['profileUrl'] ?? "";
            
            isLoadingPic = false;
          });
        } else {
          setState(() { isLoadingPic = false; });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() { isLoadingPic = false; });
        debugPrint("Error loading profile details: $e");
      }
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final XFile? image = await _profilePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image != null) {
        if (!mounted) return;
        final File? croppedFile = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageCropPage(imageFile: File(image.path)),
          ),
        );

        if (croppedFile != null) {
          if (!mounted) return;
          setState(() {
            _selectedProfileImage = croppedFile;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't select image — please try again.")),
      );
    }
  }



  @override
  void dispose() {
    nameController.dispose();
    bioController.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Text(
              "Tap to change profile picture.",
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
            ),
            const SizedBox(height: 15),
            
            // Profile Picture Container
            GestureDetector(
              onTap: _pickProfileImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    height: 140,
                    width: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.colorScheme.primary, width: 2),
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: ClipOval(
                      child: _selectedProfileImage != null
                          ? Image.file(_selectedProfileImage!, fit: BoxFit.cover)
                          : (currentCloudPicUrl.isNotEmpty
                              ? GlobalCachedImage(imageUrl: currentCloudPicUrl, fit: BoxFit.cover,
                                  errorWidget: const Icon(Icons.person, size: 70))
                              : isLoadingPic 
                                  ? const Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.person, size: 70)),
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    radius: 18,
                    child: Icon(Icons.camera_alt, color: theme.colorScheme.onPrimary, size: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: "Username / Name",
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 15),
            
            TextField(
              controller: bioController,
              maxLength: 150,
              maxLines: 4,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: InputDecoration(
                labelText: "Bio",
                hintText: "Write something about yourself...",
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide.none),
              ),
            ),
            
            
            
                  
            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: () async {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) return;

                  
                  

                  final bool? confirmSave = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Save Changes?"),
                      content: const Text(
                           "Are you sure you want to update your profile metadata changes?"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text("Cancel"),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text("Confirm Save", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );

                  if (confirmSave != true) return;

                  // 1. Show Loading Indicator immediately
                  if (!context.mounted) return;
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator()),
                  );

                  String targetProfilePicUrl = currentCloudPicUrl;

                  // 2. Process image compression and safety check
                  if (_selectedProfileImage != null) {
                    try {
                      final tempDir = await getTemporaryDirectory();
                      final compressedPath = "${tempDir.absolute.path}/profile_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg";

                      XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
                        _selectedProfileImage!.absolute.path,
                        compressedPath,
                        quality: 100,
                        format: CompressFormat.jpeg,
                      );

                      if (compressedXFile != null) {
                        File finalUploadFile = File(compressedXFile.path);
                        
                        // 🚨 ON-DEVICE SAFETY FILTER (Nudity Check) — same
                        // pipeline used for post uploads (see
                        // lib/moderation/), now the sole moderation layer
                        // since Google Vision was removed.
                        final onDeviceVerdict = await moderationPipeline.check(finalUploadFile);

                        if (!onDeviceVerdict.isSafe) {
                          // Garbage file clean up
                          if (await finalUploadFile.exists()) {
                            await finalUploadFile.delete();
                          }
                          
                          if (context.mounted) {
                            Navigator.pop(context); // Close loader
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("🚨 Upload Blocked: ${onDeviceVerdict.rejectionReason ?? "content policy violation"}"),
                                backgroundColor: AppColors.error,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                          return; // Code execution breaks here safely
                        }
                        
                        // Image safe hai, ab Cloudflare R2 par bheinjein
                        String? uploadedProfileUrl = await uploadImageToImgBB(
                          finalUploadFile,
                          folder: 'profile',
                        );
                        
                        if (uploadedProfileUrl != null) {
                          targetProfilePicUrl = uploadedProfileUrl;
                          currentUserProfile = uploadedProfileUrl; // Sync global state
                        } else {
                          if (context.mounted) {
                            Navigator.pop(context); // Close loader
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Failed to upload selected profile picture to server.")),
                            );
                          }
                          return;
                        }

                        if (await finalUploadFile.exists()) {
                          await finalUploadFile.delete();
                        }
                      }
                    } catch (compressError) {
                      debugPrint("Compression/Safety analysis failed fallback: $compressError");
                    }
                  }

                  // 3. Save Data to Supabase
                  try {
                    currentUserName = nameController.text.trim();
                    currentUserBio = bioController.text.trim();
                    
                    Map<String, dynamic> updatedFields = {
                      'userName': currentUserName,
                      'profileUrl': targetProfilePicUrl, 
                      'bio': currentUserBio,
                    };

                    await Supabase.instance.client
                        .from(kUsersCollection)
                        .update(updatedFields)
                        .eq('uid', user.id);
                    
                    // Old posts data synchronization update pipeline
                    if (_selectedProfileImage != null) {
                      await Supabase.instance.client
                          .from(kPostsCollection)
                          .update({'userPhotoUrl': targetProfilePicUrl})
                          .eq(kPostOwnerUidField, user.id);
                    }

                    if (context.mounted) Navigator.pop(context); // Close Loader

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Profile Settings Updated Successfully!")),
                      );
                      Navigator.pop(context); 
                    }
                  } catch (e) {
                    debugPrint("Error syncing profile with Supabase pipeline: $e");
                    if (context.mounted) {
                      Navigator.pop(context); // Close Loader
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Update failed — please try again.")),
                      );
                    }
                  }
                },
                child: const Text("Save Changes", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}    
