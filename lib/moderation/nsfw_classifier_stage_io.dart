import 'dart:typed_data';
import 'package:universal_io/universal_io.dart';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';
import 'moderation_result.dart';

class NsfwClassifierStage {
  final double unsafeThreshold;
  NsfwDetector? _detector;

  NsfwClassifierStage({this.unsafeThreshold = 0.7});

  Future<void> loadModel() async {
    _detector = await NsfwDetector.load(threshold: unsafeThreshold);
  }

  Future<StageResult> checkBytes(Uint8List bytes) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/proearn_moderation_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      return await check(tempFile);
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<StageResult> check(File imageFile) async {
    const stageName = 'nsfw_classifier';
    if (_detector == null) {
      return const StageResult(
        stageName: stageName,
        passed: false,
        reason: 'Detector not loaded — no moderation available, failing closed',
      );
    }
    try {
      final result = await _detector!.detectNSFWFromFile(imageFile);
      if (result == null) {
        return const StageResult(stageName: stageName, passed: false, reason: 'Detector returned no result');
      }
      final passed = !result.isNsfw;
      return StageResult(
        stageName: stageName,
        passed: passed,
        confidenceScore: result.score,
        reason: passed ? null : 'NSFW score ${result.score} >= threshold $unsafeThreshold',
      );
    } catch (e) {
      return StageResult(stageName: stageName, passed: false, reason: 'Detection error: $e');
    }
  }

  void dispose() {}
}
