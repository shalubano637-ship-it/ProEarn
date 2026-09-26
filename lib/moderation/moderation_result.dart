// =============================================================================
// PRO EARN — On-device moderation: result types
// =============================================================================

/// Result of a single pipeline stage.
class StageResult {
  final String stageName;
  final bool passed;
  final double? confidenceScore; // 0.0-1.0, null for non-ML stages (e.g. quality check)
  final String? reason;

  const StageResult({
    required this.stageName,
    required this.passed,
    this.confidenceScore,
    this.reason,
  });

  @override
  String toString() =>
      'StageResult($stageName: ${passed ? "PASS" : "FAIL"}'
      '${confidenceScore != null ? ", score=${confidenceScore!.toStringAsFixed(3)}" : ""}'
      '${reason != null ? ", reason=$reason" : ""})';
}

/// Final verdict from the full pipeline, plus every stage's individual
/// result — kept even on early-exit so the UI/logs can show exactly which
/// stage rejected the image, not just a generic "unsafe" message.
class ModerationVerdict {
  final bool isSafe;
  final List<StageResult> stageResults;
  final String? rejectionReason;

  const ModerationVerdict({
    required this.isSafe,
    required this.stageResults,
    this.rejectionReason,
  });
}
