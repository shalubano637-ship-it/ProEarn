// =============================================================================
// PRO EARN — Stage 5: rule engine
// -----------------------------------------------------------------------------
// Combines every prior stage's result into a final safe/unsafe decision.
// Deliberately not just "all stages must pass" — a rule engine earns its
// name by letting you express real policy, e.g.:
//   - Quality-check failure alone shouldn't be treated the same as a
//     nudity-classifier failure (one is "please retake this photo", the
//     other is "this content is not allowed" — different user messaging,
//     and arguably different account-strike consequences).
//   - A borderline score from ONE classifier might be fine, but borderline
//     scores from TWO classifiers simultaneously should escalate to reject
//     even if neither individually crossed its own threshold.
// =============================================================================

import 'moderation_result.dart';

class RuleEngineStage {
  /// If two or more ML-based stages (excludes the pure quality_check stage)
  /// score above this "borderline" threshold — even if none crossed their
  /// own hard threshold — the image is rejected. Catches cases where no
  /// single classifier is confident, but several are moderately suspicious.
  static const double borderlineScore = 0.35;
  static const int borderlineStagesToReject = 2;

  static ModerationVerdict decide(List<StageResult> results) {
    // Rule 1: any hard stage failure rejects immediately.
    final hardFailure = results.where((r) => !r.passed).toList();
    if (hardFailure.isNotEmpty) {
      final first = hardFailure.first;
      return ModerationVerdict(
        isSafe: false,
        stageResults: results,
        rejectionReason: '${first.stageName}: ${first.reason ?? "failed"}',
      );
    }

    // Rule 2: cumulative borderline scores across multiple ML stages.
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
