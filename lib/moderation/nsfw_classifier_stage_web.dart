import 'package:universal_io/universal_io.dart';
import 'moderation_result.dart';

class NsfwClassifierStage {
  final double unsafeThreshold;
  NsfwClassifierStage({this.unsafeThreshold = 0.7});

  Future<void> loadModel() async {}

  Future<StageResult> check(File imageFile) async {
    return const StageResult(
      stageName: 'nsfw_classifier',
      passed: false,
      reason: 'Browser NSFW classifier is not available yet',
    );
  }

  void dispose() {}
}
