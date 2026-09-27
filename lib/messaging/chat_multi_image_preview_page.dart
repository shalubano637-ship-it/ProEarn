
import 'package:universal_io/universal_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/theme.dart';
import '../service.dart';
import '../moderation/moderation_config.dart';

Future<List<String>?> showChatMultiImagePreview(BuildContext context, List<File> imageFiles) {
  return Navigator.push<List<String>?>(
    context,
    MaterialPageRoute(builder: (_) => _ChatMultiImagePreviewPage(imageFiles: imageFiles)),
  );
}

enum _ItemState { checking, safe, unsafe, failed }

class _Item {
  final File original;
  _ItemState state = _ItemState.checking;
  String? rejectionReason;
  File? compressed;
  _Item(this.original);
}

class _ChatMultiImagePreviewPage extends StatefulWidget {
  final List<File> imageFiles;
  const _ChatMultiImagePreviewPage({required this.imageFiles});

  @override
  State<_ChatMultiImagePreviewPage> createState() => _ChatMultiImagePreviewPageState();
}

class _ChatMultiImagePreviewPageState extends State<_ChatMultiImagePreviewPage> {
  late List<_Item> _items;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _items = widget.imageFiles.map((f) => _Item(f)).toList();
    for (final item in _items) {
      _runChecks(item);
    }
  }

  Future<void> _runChecks(_Item item) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = "${dir.absolute.path}/chat_send_${DateTime.now().microsecondsSinceEpoch}.jpg";

      final compressedXFile = await FlutterImageCompress.compressAndGetFile(
        item.original.absolute.path,
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
        item.compressed = compressed;
        item.state = verdict.isSafe ? _ItemState.safe : _ItemState.unsafe;
        item.rejectionReason = verdict.rejectionReason;
      });
    } catch (e) {
      if (mounted) setState(() { item.state = _ItemState.failed; });
    }
  }

  void _removeItem(_Item item) {
    setState(() { _items.remove(item); });
    if (_items.isEmpty && mounted) Navigator.pop(context, <String>[]);
  }

  bool get _anyStillChecking => _items.any((i) => i.state == _ItemState.checking);
  List<_Item> get _sendableItems => _items.where((i) => i.state == _ItemState.safe).toList();

  Future<void> _send() async {
    if (_anyStillChecking || _sendableItems.isEmpty || _isSending) return;
    setState(() { _isSending = true; });

    final urls = <String>[];
    try {
      for (final item in _sendableItems) {
        final url = await uploadImageToMediaGateway(item.compressed!, folder: 'chat');
        if (url != null) urls.add(url);
      }
      if (mounted) Navigator.pop(context, urls);
    } catch (e) {
      if (mounted) {
        setState(() { _isSending = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Some images failed to send (${urls.length}/${_sendableItems.length} sent)."), backgroundColor: AppColors.error),
        );
        if (urls.isNotEmpty) Navigator.pop(context, urls); // still deliver whatever did make it
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.close), tooltip: "Cancel", onPressed: () => Navigator.pop(context)),
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
                        opacity: item.state == _ItemState.unsafe || item.state == _ItemState.failed ? 0.35 : 1,
                        child: Image.file(item.original, fit: BoxFit.cover),
                      ),
                    ),
                    if (item.state == _ItemState.checking)
                      const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                    if (item.state == _ItemState.unsafe)
                      const Center(child: Icon(Icons.block, color: AppColors.error)),
                    if (item.state == _ItemState.failed)
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
          if (_items.any((i) => i.state == _ItemState.unsafe))
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Text(
                "Some photos can't be sent — remove them (✕) to send the rest.",
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
                  onPressed: (!_anyStillChecking && _sendableItems.isNotEmpty && !_isSending) ? _send : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: AppColors.textTertiary,
                  ),
                  child: _isSending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text("Send ${_sendableItems.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
