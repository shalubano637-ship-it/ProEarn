
import 'moderation_result.dart';

class RuleEngineStage {
  static const double borderlineScore = 0.35;
  static const int borderlineStagesToReject = 2;

  static ModerationVerdict decide(List<StageResult> results) {
    final hardFailure = results.where((r) => !r.passed).toList();
    if (hardFailure.isNotEmpty) {
      final first = hardFailure.first;
      return ModerationVerdict(
        isSafe: false,
        stageResults: results,
        rejectionReason: '${first.stageName}: ${first.reason ?? "failed"}',
      );
    }

    final borderlineCount = results
        .where((r) => r.confidenceScore != null && r.confidenceScore! >= borderlineScore)
        .length;
    if (borderlineCount >= borderlineStagesToReject) {
      return ModerationVerdict(
        isSafe: false,
        stageResults: results,
        rejectionReason:
            '$borderlineCount classifiers scored above the borderline threshold ($borderlineScore)',
      );
    }

    return ModerationVerdict(isSafe: true, stageResults: results);
  }
}
