
import 'package:universal_io/universal_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/theme.dart';
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

enum _PrepareState { preparing, ready, failed }

class _ChatImagePreviewPageState extends State<_ChatImagePreviewPage> {
  _PrepareState _state = _PrepareState.preparing;
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
      final targetPath = "${dir.path}/chat_send_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final compressed = await FlutterImageCompress.compressAndGetFile(
        widget.imageFile.absolute.path,
        targetPath,
        quality: 70,
        minWidth: 1080,
        format: CompressFormat.jpeg,
      );
      if (compressed == null) throw StateError("Image compression failed");
      if (!mounted) return;
      setState(() {
        _compressedFile = File(compressed.path);
        _state = _PrepareState.ready;
      });
    } catch (e) {
      debugPrint("Chat image preparation failed: $e");
      if (mounted) setState(() => _state = _PrepareState.failed);
    }
  }

  Future<void> _send() async {
    final file = _compressedFile;
    if (_state != _PrepareState.ready || file == null || _isSending) return;
    setState(() => _isSending = true);
    try {
      final url = await CloudflareMediaService.uploadImage(file, folder: 'chat');
      if (!mounted) return;
      Navigator.pop(context, url);
    } catch (e, st) {
      debugPrint("Chat image upload failed: $e");
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Image upload failed: $e"),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _state == _PrepareState.ready && !_isSending;
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
            child: Center(child: Image.file(widget.imageFile, fit: BoxFit.contain)),
          ),
          if (_state == _PrepareState.preparing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: AppSpacing.sm),
                  Text("Preparing image...", style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                ],
              ),
            ),
          if (_state == _PrepareState.failed)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Expanded(child: Text("Couldn't prepare this image. Please retry.")),
                  TextButton(
                    onPressed: () {
                      setState(() => _state = _PrepareState.preparing);
                      _prepareImage();
                    },
                    child: const Text("Retry"),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: ready ? _send : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: AppColors.textTertiary,
                  ),
                  child: _isSending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Send", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
