import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_util' as js_util;
import 'package:universal_io/universal_io.dart';
import 'moderation_result.dart';

class NsfwClassifierStage {
  final double unsafeThreshold;
  NsfwClassifierStage({this.unsafeThreshold = 0.7});

  Future<void> loadModel() async {
    try {
      await js_util.promiseToFuture(
        js_util.callMethod(js_util.globalThis, 'proEarnNsfwLoad', const []),
      );
    } catch (e) {
      throw StateError('Browser NSFW model failed to load: $e');
    }
  }

  Future<StageResult> check(File imageFile) async {
    return checkBytes(await imageFile.readAsBytes());
  }

  Future<StageResult> checkBytes(Uint8List bytes) async {
    const stageName = 'nsfw_classifier';
    try {
      final raw = await js_util.promiseToFuture<String>(
        js_util.callMethod(js_util.globalThis, 'proEarnNsfwCheck', [base64Encode(bytes)]),
      );
      final result = jsonDecode(raw) as Map<String, dynamic>;
      final unsafeScore = (result['unsafeScore'] as num?)?.toDouble() ?? 1.0;
      final topClass = result['topClass']?.toString() ?? 'Unknown';
      final topProbability = (result['topProbability'] as num?)?.toDouble() ?? unsafeScore;
      final passed = unsafeScore < unsafeThreshold;
      return StageResult(
        stageName: stageName,
        passed: passed,
        confidenceScore: topProbability,
        reason: passed ? null : 'Browser NSFW score $unsafeScore >= threshold $unsafeThreshold ($topClass)',
      );
    } catch (e) {
      return StageResult(stageName: stageName, passed: false, reason: 'Browser detection unavailable: $e');
    }
  }

  void dispose() {}
}
