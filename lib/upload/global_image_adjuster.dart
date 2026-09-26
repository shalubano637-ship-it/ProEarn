// =============================================================================
// PRO EARN — Upload: GlobalImageAdjuster
// -----------------------------------------------------------------------------
// Extracted from the original social_feed.dart during the feature-based
// file split (no UI or logic changes — only where this code physically
// lives). social_feed.dart is now a barrel file that re-exports this file.
// =============================================================================

// =============================================================================
// PRO EARN — AI-generated content social platform
// -----------------------------------------------------------------------------
// This file (social_feed.dart) is one of three files this app's UI/logic
// was split into (equal three-way split of the original single-file
// main.dart, no UI or logic changes — only where each class physically
// lives):
//   1. main.dart
//   2. social_feed.dart            (this file)
//   3. user_profile_features.dart
//
// social_feed.dart contains everything about browsing, creating, and
// interacting with posts/reels:
//   - Feed & Reels: ReelsPage, SearchPage, SingleReelScreen
//   - Upload & Media: UploadPage, GlobalImageAdjuster
//   - Post interactions: LikeButton, CommentButton, CommentScreen,
//     ShareButton, MoreOptionsButton, GetPromptButton (creator earnings)
//
// Persistence: Supabase (Postgres) is the source of truth for all
// user/post/social data.
// =============================================================================

// ---- Dart core ----
import 'dart:async';
import 'package:universal_io/universal_io.dart';
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



class GlobalImageAdjuster extends StatefulWidget {
  final File imageFile;
  final Function(File) onConfirm;

  const GlobalImageAdjuster({
    super.key,
    required this.imageFile,
    required this.onConfirm,
  });

  @override
  State<GlobalImageAdjuster> createState() => _GlobalImageAdjusterState();
}
class _GlobalImageAdjusterState extends State<GlobalImageAdjuster> {
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _repaintKey = GlobalKey();

  Future<void> _cropAndSaveImage() async {
    try {
      RenderRepaintBoundary? boundary =
          _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      Uint8List pngBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      File file = await File('${tempDir.path}/cropped_post_${DateTime.now().millisecondsSinceEpoch}.png')
          .create();
      await file.writeAsBytes(pngBytes);

      widget.onConfirm(file);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error cropping post image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: const Text("Adjust 9:16 Post Size"),
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
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Container(
              // FIX: Border ko BoxDecoration ke andar wrap kar diya hai
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border, width: 1.0),
              ),
              child: ClipRect(
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    clipBehavior: Clip.none,
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: SizedBox.expand(
                      child: Image.file(
                        widget.imageFile,
                        fit: BoxFit.contain, 
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
