import 'nsfw_classifier_stage.dart';
import 'on_device_moderation_pipeline.dart';

final OnDeviceModerationPipeline moderationPipeline = OnDeviceModerationPipeline(
  nsfwClassifier: NsfwClassifierStage(unsafeThreshold: 0.7),
);
