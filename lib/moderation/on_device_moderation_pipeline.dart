// =============================================================================
// PRO EARN — On-device image moderation pipeline
// -----------------------------------------------------------------------------
//   Image
//     ↓
//   1. Image quality / size check      (stage1_quality_check.dart — pure Dart)
//     ↓
//   2. NSFW classifier                  (nsfw_classifier_stage.dart —
//      uses the nsfw_detector_flutter package, which bundles its own
//      model; no manual .tflite sourcing needed)
//     ↓
//   3. Rule engine                      (stage5_rule_engine.dart)
//     ↓
//   Safe → Upload / Unsafe → Reject
//
// *** GOOGLE VISION REMOVED — THIS IS NOW THE ONLY MODERATION LAYER ***
// Google Cloud Vision (the server-side check-image-safety function) has
// been removed entirely, per explicit instruction. This means:
//   - This pipeline runs ENTIRELY on the user's device, no network call,
//     no third-party API, no per-request cost.
//   - It is now STRICTLY fail-closed: if the model isn't loaded (missing
//     asset, corrupt file, wrong path), every image is rejected — there
//     is no server-side fallback anymore, so "fail open" would mean zero
//     moderation exists at all.
//   - A modified/patched client CAN bypass this check entirely, since it
//     runs in the user's own app process with no server-side enforcement
//     backing it up anymore. This is an accepted, explicit trade-off of
//     removing Vision — worth knowing, not a bug.
// =============================================================================

import 'package:universal_io/universal_io.dart';
import 'moderation_result.dart';
import 'stage1_quality_check.dart';
import 'nsfw_classifier_stage.dart';
import 'stage5_rule_engine.dart';

class OnDeviceModerationPipeline {
  final NsfwClassifierStage nsfwClassifier;

  bool _modelLoaded = false;

  OnDeviceModerationPipeline({required this.nsfwClassifier});

  /// Call once at app startup (or lazily before the first upload) — model
  /// loading takes real time (reading + parsing the .tflite file), so
  /// don't call this per-image.
  Future<void> initialize() async {
    if (_modelLoaded) return;
    await nsfwClassifier.loadModel();
    _modelLoaded = true;
  }

  Future<ModerationVerdict> check(File imageFile) async {
    final results = <StageResult>[];

    // Stage 1 — cheap, pure Dart. Early-exit here: no point running the ML
    // inference on an image that's already going to be rejected for being
    // corrupted/too small/too large.
    final qualityResult = await QualityCheckStage.check(imageFile);
    results.add(qualityResult);
    if (!qualityResult.passed) {
      return RuleEngineStage.decide(results);
    }

    // Stage 2 — the NSFW classifier itself fails closed internally if
    // _modelLoaded is false (see NsfwClassifierStage.check), so no
    // separate "model not loaded" branch is needed here — every path
    // through this method always actually runs a real check.
    results.add(await nsfwClassifier.check(imageFile));

    return RuleEngineStage.decide(results);
  }

  void dispose() {
    nsfwClassifier.dispose();
    _modelLoaded = false;
  }
}
