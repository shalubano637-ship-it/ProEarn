
import 'package:universal_io/universal_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/theme.dart';
import '../cloudflare_media_service.dart';

Future<List<String>?> showChatMultiImagePreview(BuildContext context, List<File> imageFiles) {
  return Navigator.push<List<String>?>(
    context,
    MaterialPageRoute(builder: (_) => _ChatMultiImagePreviewPage(imageFiles: imageFiles)),
  );
}

enum _PrepareState { preparing, ready, failed }

class _ImageItem {
  final File original;
  _PrepareState state = _PrepareState.preparing;
  File? compressed;
  _ImageItem(this.original);
}

class _ChatMultiImagePreviewPage extends StatefulWidget {
  final List<File> imageFiles;
  const _ChatMultiImagePreviewPage({required this.imageFiles});

  @override
  State<_ChatMultiImagePreviewPage> createState() => _ChatMultiImagePreviewPageState();
}

class _ChatMultiImagePreviewPageState extends State<_ChatMultiImagePreviewPage> {
  late final List<_ImageItem> _items;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _items = widget.imageFiles.map(_ImageItem.new).toList();
    for (final item in _items) {
      _prepareImage(item);
    }
  }

  Future<void> _prepareImage(_ImageItem item) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = "${dir.path}/chat_send_${DateTime.now().microsecondsSinceEpoch}.jpg";
      final compressed = await FlutterImageCompress.compressAndGetFile(
        item.original.absolute.path,
        targetPath,
        quality: 70,
        minWidth: 1080,
        format: CompressFormat.jpeg,
      );
      if (compressed == null) throw StateError("Image compression failed");
      if (!mounted) return;
      setState(() {
        item.compressed = File(compressed.path);
        item.state = _PrepareState.ready;
      });
    } catch (e) {
      debugPrint("Chat image preparation failed: $e");
      if (mounted) setState(() => item.state = _PrepareState.failed);
    }
  }

  void _removeItem(_ImageItem item) {
    setState(() => _items.remove(item));
    if (_items.isEmpty && mounted) Navigator.pop(context, <String>[]);
  }

  bool get _anyStillPreparing => _items.any((item) => item.state == _PrepareState.preparing);
  List<_ImageItem> get _readyItems => _items.where((item) => item.state == _PrepareState.ready && item.compressed != null).toList();

  Future<void> _send() async {
    final sendable = _readyItems;
    if (_anyStillPreparing || sendable.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    final urls = <String>[];
    try {
      for (final item in sendable) {
        final url = await CloudflareMediaService.uploadImage(item.compressed!, folder: 'chat');
        urls.add(url);
      }
      if (mounted) Navigator.pop(context, urls);
    } catch (e, st) {
      debugPrint("Chat multi-image upload failed: $e");
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Image upload failed (${urls.length}/${sendable.length} sent): $e"),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 8),
        ),
      );
      if (urls.isNotEmpty) Navigator.pop(context, urls);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readyItems = _readyItems;
    final canSend = !_anyStillPreparing && readyItems.isNotEmpty && !_isSending;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: "Cancel",
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("${_items.length} photo${_items.length == 1 ? '' : 's'}"),
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Opacity(
                        opacity: item.state == _PrepareState.failed ? 0.35 : 1,
                        child: Image.file(item.original, fit: BoxFit.cover),
                      ),
                    ),
                    if (item.state == _PrepareState.preparing)
                      const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                    if (item.state == _PrepareState.failed)
                      const Center(child: Icon(Icons.error_outline, color: Colors.white)),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _removeItem(item),
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_items.any((item) => item.state == _PrepareState.failed))
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Text(
                "Some photos couldn't be prepared. Remove them to send the rest.",
                style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
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
                  onPressed: canSend ? _send : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: AppColors.textTertiary,
                  ),
                  child: _isSending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text("Send ${readyItems.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
