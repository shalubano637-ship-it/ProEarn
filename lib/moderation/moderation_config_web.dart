import 'nsfw_classifier_stage.dart';
import 'on_device_moderation_pipeline.dart';

// Web cannot load the native TFLite/FFI classifier. Keep the same pipeline
// contract so the rest of the app compiles on Web. The web classifier fails
// closed until a browser-compatible classifier is added.
final OnDeviceModerationPipeline moderationPipeline = OnDeviceModerationPipeline(
  nsfwClassifier: NsfwClassifierStage(unsafeThreshold: 0.7),
);
