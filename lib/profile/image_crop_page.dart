// =============================================================================
// PRO EARN — Profile: ImageCropPage
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
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

// ---- Flutter framework ----
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// ---- Third-party packages ----
import 'package:path_provider/path_provider.dart';

// ---- App files (split out of the original single-file main.dart) ----
import '../theme/theme.dart';

// ================= STANDALONE REELS VIEWER (deep-linked / profile grid) =================
 class ImageCropPage extends StatefulWidget {
  final File imageFile;
  const ImageCropPage({super.key, required this.imageFile});

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}
 class _ImageCropPageState extends State<ImageCropPage> {
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _boundaryKey = GlobalKey();

  Future<void> _cropAndSaveImage() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      RenderRepaintBoundary boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0); // Better quality resolution
      
      // FIX: rawRgba ki jagah .png format ka use karein taaki sahi se file encode ho
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        
        final tempDir = await getTemporaryDirectory();
        // PNG bytes hain isliye filename extension .png rakhein
        final File croppedFile = File('${tempDir.path}/cropped_profile_${DateTime.now().millisecondsSinceEpoch}.png');
        await croppedFile.writeAsBytes(pngBytes);

        if (mounted) {
          Navigator.pop(context); // Loader band karein
          Navigator.pop(context, croppedFile); // Cropped file wapas bhejein
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't crop image — please try again.")),
        );
      }
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ... baki pura build UI widget same rahega jaisa aapka pehle tha
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: const Text("Move and Scale"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, size: 28, color: AppColors.success),
            tooltip: "Confirm crop",
            onPressed: _cropAndSaveImage,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: RepaintBoundary(
            key: _boundaryKey,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  // NOTE: crop canvas + mask below intentionally use literal
                  // black/white (not theme tokens) — this is a functional
                  // image-cropping overlay, not themed UI chrome.
                  Container(color: Colors.black),
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      maxScale: 5.0,
                      minScale: 1.0,
                      boundaryMargin: const EdgeInsets.all(200.0),
                      child: Center(
                        child: Image.file(
                          widget.imageFile,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(0.7), 
                        BlendMode.srcOut,
                      ),
                      child: Stack(
                        children: [
                          Container(color: AppColors.transparent),
                          Center(
                            child: Container(
                              width: double.infinity,
                              height: double.infinity,
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle, 
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.9), width: 2.0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
