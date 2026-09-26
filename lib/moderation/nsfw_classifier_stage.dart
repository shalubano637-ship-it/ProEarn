// =============================================================================
// PRO EARN — NSFW classifier stage (nsfw_detector_flutter)
// -----------------------------------------------------------------------------
// Uses the nsfw_detector_flutter package (pub.dev), which bundles its own
// TFLite model internally — "without downloading or setting any assets"
// per its own docs. This replaces an earlier hand-rolled TFLite
// integration that needed a manually-sourced model file; that manual
// sourcing step is no longer needed at all.
// =============================================================================

import 'dart:io';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';
import 'moderation_result.dart';

class NsfwClassifierStage {
  final double unsafeThreshold;

  NsfwDetector? _detector;

  NsfwClassifierStage({this.unsafeThreshold = 0.7}); // package's own documented default

  Future<void> loadModel() async {
    _detector = await NsfwDetector.load(threshold: unsafeThreshold);
  }

  Future<StageResult> check(File imageFile) async {
    const stageName = 'nsfw_classifier';

    if (_detector == null) {
      // Fail-closed: this is the only moderation layer now that Google
      // Vision has been removed — an unloaded detector must reject, never
      // silently pass.
      return const StageResult(
        stageName: stageName,
        passed: false,
        reason: 'Detector not loaded — no moderation available, failing closed',
      );
    }

    try {
      final result = await _detector!.detectNSFWFromFile(imageFile);
      if (result == null) {
        // The package itself couldn't produce a result (e.g. decode
        // failure) — fail closed rather than assume safe.
        return const StageResult(stageName: stageName, passed: false, reason: 'Detector returned no result');
      }

      final bool passed = !result.isNsfw;
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

  void dispose() {
    // NsfwDetector doesn't currently expose a dispose method in its public
    // API — nothing to release here, kept for interface symmetry with the
    // rest of the pipeline (on_device_moderation_pipeline.dart calls this
    // unconditionally on its own dispose()).
  }
}
