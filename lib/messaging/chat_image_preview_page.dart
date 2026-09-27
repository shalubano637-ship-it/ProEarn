
import 'package:universal_io/universal_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/theme.dart';
import '../service.dart';
import '../moderation/moderation_config.dart';

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

enum _CheckState { checking, safe, unsafe, failed }

class _ChatImagePreviewPageState extends State<_ChatImagePreviewPage> {
  _CheckState _checkState = _CheckState.checking;
  String? _rejectionReason;
  File? _compressedFile;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
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

      final verdict = await moderationPipeline.check(compressed);

      if (!mounted) return;
      setState(() {
        _compressedFile = compressed;
        _checkState = verdict.isSafe ? _CheckState.safe : _CheckState.unsafe;
        _rejectionReason = verdict.rejectionReason;
      });
    } catch (e) {
      if (mounted) setState(() { _checkState = _CheckState.failed; });
    }
  }

  Future<void> _send() async {
    if (_checkState != _CheckState.safe || _compressedFile == null || _isSending) return;
    setState(() { _isSending = true; });

    try {
      final url = await uploadImageToMediaGateway(_compressedFile!, folder: 'chat');
      if (url == null) throw Exception("Upload failed");
      if (mounted) Navigator.pop(context, url);
    } catch (e) {
      if (mounted) {
        setState(() { _isSending = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send image — please try again."), backgroundColor: AppColors.error),
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
          if (_checkState == _CheckState.checking)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textTertiary)),
                  SizedBox(width: AppSpacing.sm),
                  Text("Checking image...", style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                ],
              ),
            ),
          if (_checkState == _CheckState.unsafe)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.15),
                borderRadius: AppRadius.mdRadius,
                border: Border.all(color: AppColors.error),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _rejectionReason ?? "This image can't be sent — it may contain content that isn't allowed.",
                      style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (_checkState == _CheckState.failed)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: AppRadius.mdRadius),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.textTertiary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text("Couldn't check this image — try again.", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: () => setState(() { _checkState = _CheckState.checking; _runChecks(); }),
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
                  onPressed: _canSend ? _send : null,
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
