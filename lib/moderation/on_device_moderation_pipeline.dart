
import 'package:universal_io/universal_io.dart';
import 'moderation_result.dart';
import 'stage1_quality_check.dart';
import 'nsfw_classifier_stage.dart';
import 'stage5_rule_engine.dart';

class OnDeviceModerationPipeline {
  final NsfwClassifierStage nsfwClassifier;

  bool _modelLoaded = false;

  OnDeviceModerationPipeline({required this.nsfwClassifier});

  Future<void> initialize() async {
    if (_modelLoaded) return;
    await nsfwClassifier.loadModel();
    _modelLoaded = true;
  }

  Future<ModerationVerdict> check(File imageFile) async {
    final results = <StageResult>[];

    final qualityResult = await QualityCheckStage.check(imageFile);
    results.add(qualityResult);
    if (!qualityResult.passed) {
      return RuleEngineStage.decide(results);
    }

    results.add(await nsfwClassifier.check(imageFile));

    return RuleEngineStage.decide(results);
  }

  void dispose() {
    nsfwClassifier.dispose();
    _modelLoaded = false;
  }
}
