// =============================================================================
// PRO EARN — Moderation pipeline configuration
// -----------------------------------------------------------------------------
// nsfw_detector_flutter bundles its own model internally — no asset path
// to configure, no manual model file to source. If initialize() still
// fails (extremely unlikely, but possible on a corrupted install), the
// pipeline fails closed exactly like before (see
// on_device_moderation_pipeline.dart) — blocking uploads rather than
// silently skipping moderation, since Google Vision is no longer there as
// a fallback.
// =============================================================================

import 'nsfw_classifier_stage.dart';
import 'on_device_moderation_pipeline.dart';

final OnDeviceModerationPipeline moderationPipeline = OnDeviceModerationPipeline(
  nsfwClassifier: NsfwClassifierStage(
    unsafeThreshold: 0.7, // package's documented default — tune against your own test images if needed
  ),
);
