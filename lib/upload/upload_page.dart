

import 'dart:async';
import 'package:universal_io/universal_io.dart';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../service.dart';
import '../theme/theme.dart';
import '../moderation/moderation_config.dart';

import 'global_image_adjuster.dart';

       class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}
class _UploadPageState extends State<UploadPage> {
  File? _pickedImageFile;
  final ImagePicker _picker = ImagePicker();
  
  final TextEditingController promptController = TextEditingController();
  final TextEditingController captionController = TextEditingController();
  final TransformationController _transformationController = TransformationController();
  
  double _uploadPercentage = 0.0;
  bool _isUploading = false;
  String _uploadStatusText = "";

  Future<void> pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
      );

      if (image != null) {
        File originalFile = File(image.path);
        _transformationController.value = Matrix4.identity();
        
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GlobalImageAdjuster(
                imageFile: originalFile,
                onConfirm: (File croppedFile) {
                  setState(() {
                    _pickedImageFile = croppedFile;
                  });
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't select image — please try again.")),
      );
    }
  }

  void createPost() async {
    final prompt = promptController.text.trim(); 
    final caption = captionController.text.trim(); 

    if (_pickedImageFile == null) { 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select image first")), 
      );
      return;
    }

    if (prompt.length < 20) { 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Prompt must be minimum 20 characters")), 
      );
      return;
    }
     
    if (Supabase.instance.client.auth.currentUser == null) return;

    setState(() {
      _isUploading = true;
      _uploadPercentage = 0.0;
      _uploadStatusText = "Optimizing image...";
    });
    
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = "${dir.absolute.path}/temp_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg";

      XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
        _pickedImageFile!.absolute.path,
        targetPath,
        quality: 65, // Fast processing optimization
        minWidth: 1080, // Downscale max widths
        format: CompressFormat.jpeg,
      );

      if (compressedXFile == null) {
        throw Exception("Compression failed");
      }

      File finalCompressedFile = File(compressedXFile.path);

      setState(() {
        _uploadStatusText = "Checking security policy...";
      });

      final onDeviceVerdict = await moderationPipeline.check(finalCompressedFile);
      if (!onDeviceVerdict.isSafe) {
        if (await finalCompressedFile.exists()) {
          await finalCompressedFile.delete();
        }
        setState(() { _isUploading = false; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("🚨 Upload Blocked: ${onDeviceVerdict.rejectionReason ?? "content policy violation"}"),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      setState(() {
        _uploadStatusText = "Uploading and server-checking...";
      });

      final postLink = "app://post/${DateTime.now().millisecondsSinceEpoch}";
      final imageUrl = await uploadImageToMediaGateway(
        finalCompressedFile,
        folder: 'posts',
        onProgress: (bytes, total) {
          if (mounted && total > 0) {
            setState(() => _uploadPercentage = (bytes / total) * 100);
          }
        },
      );

      if (imageUrl == null || imageUrl.isEmpty) {
        throw StateError("Image upload failed");
      }

      await Supabase.instance.client.from(kPostsCollection).insert({
        'userName': Supabase.instance.client.auth.currentUser!.id,
        'caption': caption.isEmpty ? "No Caption" : caption,
        'prompt': prompt,
        'link': postLink,
        'imageUrl': imageUrl,
      });

      if (await finalCompressedFile.exists()) {
        await finalCompressedFile.delete();
      }

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _pickedImageFile = null; 
      });
      
      promptController.clear(); 
      captionController.clear(); 

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Post Uploaded successfully")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _isUploading = false; });
      final isModerationRejection = e is PostgrestException &&
          (e.message.contains('Content rejected') || e.code == 'P0001');
      debugPrint("Upload failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isModerationRejection
                ? "Post not allowed: caption or prompt contains blocked content."
                : "Upload failed — please try again.",
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }  

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_isUploading)
            Card(
              margin: const EdgeInsets.only(bottom: 20),
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_uploadStatusText, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text("${_uploadPercentage.toStringAsFixed(0)}%"),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _uploadPercentage / 100,
                      backgroundColor: theme.colorScheme.outlineVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),

          GestureDetector(
            onTap: _isUploading ? null : pickImageFromGallery,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.lgRadius,
                      border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _pickedImageFile == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_upload_outlined, size: 60, color: theme.colorScheme.onSurface),
                              const SizedBox(height: 10),
                              const Text("Select Photo"),
                            ],
                          )
                        : Stack(
                            children: [
                              Positioned.fill(
                                child: Image.file(_pickedImageFile!, fit: BoxFit.cover),
                              ),
                              if (!_isUploading)
                                Positioned(
                                  right: 10,
                                  top: 10,
                                  child: CircleAvatar(
                                    backgroundColor: AppColors.overlay,
                                    child: IconButton(
                                      icon: const Icon(Icons.edit, color: AppColors.textPrimary, size: 20),
                                      tooltip: "Change image",
                                      onPressed: pickImageFromGallery,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 25),
          TextField(
            controller: promptController,
            maxLines: 3,
            enabled: !_isUploading,
            decoration: InputDecoration(
              hintText: "Enter Prompt (Minimum 20 letters)",
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: captionController,
            enabled: !_isUploading,
            decoration: InputDecoration(
              hintText: "Caption (Optional)",
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              onPressed: _isUploading ? null : createPost,
              child: _isUploading 
                ? const SizedBox(
                    height: 24, 
                    width: 24, 
                    child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)
                  )
                : const Text("POST", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
