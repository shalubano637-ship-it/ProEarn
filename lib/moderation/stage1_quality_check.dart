
import 'dart:typed_data';
import 'package:universal_io/universal_io.dart';
import 'package:image/image.dart' as img;
import 'moderation_result.dart';

class QualityCheckStage {
  static const int minWidthPx = 200;
  static const int minHeightPx = 200;
  static const int maxFileBytes = 9 * 1024 * 1024; // matches imgbb-upload's server-side ceiling
  static const double maxAspectRatio = 4.0; // width:height or height:width, whichever is larger

  static Future<StageResult> check(File imageFile) async {
    const stageName = 'quality_check';

    final int fileSize = await imageFile.length();
    if (fileSize > maxFileBytes) {
      return const StageResult(
        stageName: stageName,
        passed: false,
        reason: 'File too large',
      );
    }
    if (fileSize == 0) {
      return const StageResult(
        stageName: stageName,
        passed: false,
        reason: 'Empty or corrupted file',
      );
    }

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const StageResult(
        stageName: stageName,
        passed: false,
        reason: 'Unrecognized or corrupted image format',
      );
    }

    if (decoded.width < minWidthPx || decoded.height < minHeightPx) {
      return const StageResult(
        stageName: stageName,
        passed: false,
        reason: 'Image resolution too low',
      );
    }

    final aspectRatio = decoded.width > decoded.height
        ? decoded.width / decoded.height
        : decoded.height / decoded.width;
    if (aspectRatio > maxAspectRatio) {
      return const StageResult(
        stageName: stageName,
        passed: false,
        reason: 'Aspect ratio too extreme',
      );
    }

    return const StageResult(stageName: stageName, passed: true);
  }

  static Future<StageResult> checkBytes(Uint8List bytes) async {
    const stageName = 'quality_check';
    if (bytes.length > maxFileBytes) return const StageResult(stageName: stageName, passed: false, reason: 'File too large');
    if (bytes.isEmpty) return const StageResult(stageName: stageName, passed: false, reason: 'Empty or corrupted file');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const StageResult(stageName: stageName, passed: false, reason: 'Unrecognized or corrupted image format');
    if (decoded.width < minWidthPx || decoded.height < minHeightPx) {
      return const StageResult(stageName: stageName, passed: false, reason: 'Image resolution too low');
    }
    final aspectRatio = decoded.width > decoded.height
        ? decoded.width / decoded.height
        : decoded.height / decoded.width;
    if (aspectRatio > maxAspectRatio) return const StageResult(stageName: stageName, passed: false, reason: 'Aspect ratio too extreme');
    return const StageResult(stageName: stageName, passed: true);
  }
}
