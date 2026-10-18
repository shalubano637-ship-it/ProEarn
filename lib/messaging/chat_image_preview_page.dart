
import 'package:universal_io/universal_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/theme.dart';
import '../service.dart';
import '../cloudflare_media_service.dart';

Future<String?> showChatImagePreview(BuildContext context, File imageFile) {
  return Navigator.push<String?>(
    context,
    MaterialPageRoute(builder: (_) => _ChatImagePreviewPage(imageFile: imageFile)),
  );
}

class _ChatImagePreviewPage extends StatefulWidget {
  final File imageFile;
  const _ChatImagePreviewPage({required this.imageFile});

  @override
  State<_ChatImagePreviewPage> createState() => _ChatImagePreviewPageState();
}

enum _CheckState { preparing, ready, failed }

class _ChatImagePreviewPageState extends State<_ChatImagePreviewPage> {
  _CheckState _checkState = _CheckState.preparing;
  File? _compressedFile;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _prepareImage();
  }

  Future<void> _prepareImage() async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = "${dir.absolute.path}/chat_send_${DateTime.now().millisecondsSinceEpoch}.jpg";

      final compressedXFile = await FlutterImageCompress.compressAndGetFile(
        widget.imageFile.absolute.path,
        targetPath,
        quality: 70,
        minWidth: 1080,
        format: CompressFormat.jpeg,
      );

      if (compressedXFile == null) throw Exception("Compression failed");
      final compressed = File(compressedXFile.path);

      if (!mounted) return;
      setState(() {
        _compressedFile = compressed;
        _checkState = _CheckState.ready;
      });
    } catch (e) {
      if (mounted) setState(() { _checkState = _CheckState.failed; });
    }
  }

  Future<void> _send() async {
    if (_checkState != _CheckState.ready || _compressedFile == null || _isSending) return;
    setState(() { _isSending = true; });

    try {
      final url = await CloudflareMediaService.uploadImage(_compressedFile!, folder: 'chat');
      if (url == null) throw Exception("Upload failed");
      if (mounted) Navigator.pop(context, url);
    } catch (e, st) {
      debugPrint("Chat image upload failed: $e");
      debugPrintStack(stackTrace: st);
      if (mounted) {
        setState(() { _isSending = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Image upload failed: $e"), backgroundColor: AppColors.error, duration: const Duration(seconds: 8)),
        );
      }
    }
  }

  bool get _canSend => _checkState == _CheckState.safe && !_isSending;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: "Cancel",
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Preview"),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Image.file(widget.imageFile, fit: BoxFit.contain),
            ),
          ),
          if (_checkState == _CheckState.preparing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textTertiary)),
                  SizedBox(width: AppSpacing.sm),
                  Text("Preparing image...", style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
