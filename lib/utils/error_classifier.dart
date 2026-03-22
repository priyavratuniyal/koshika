/// Utility class that converts raw exceptions from AI model operations
/// into user-readable error messages.
///
/// Centralising these strings makes them easy to localise later and ensures
/// consistent wording across the Gemma and Embedding services.
abstract final class ErrorClassifier {
  // ── Download errors ──────────────────────────────────────────────────

  /// Classify a download failure for a model with the given [estimatedSizeMB].
  static String download(dynamic error, {required int estimatedSizeMB}) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('socket') || msg.contains('connection')) {
      return 'Network error. Please check your internet connection and try again.';
    }
    if (msg.contains('storage') ||
        msg.contains('space') ||
        msg.contains('no space')) {
      return 'Insufficient storage. The model requires ~${estimatedSizeMB}MB of free space.';
    }
    if (msg.contains('timeout')) {
      return 'Download timed out. Please try again on a stable connection.';
    }
    if (msg.contains('403') || msg.contains('forbidden')) {
      return 'Access denied. Your Hugging Face account needs access to the model repo, '
          'and your token must have read permission.';
    }
    if (msg.contains('401') || msg.contains('unauthorized')) {
      return 'Authentication failed. Re-check your Hugging Face token and confirm '
          'it has read access to the required repos.';
    }
    if (msg.contains('404') || msg.contains('not found')) {
      return 'Model file not found at the download URL. It may have been moved or removed.';
    }
    final raw = error.toString();
    return 'Download failed: ${raw.length > 100 ? '${raw.substring(0, 100)}...' : raw}';
  }

  // ── Load / inference errors ──────────────────────────────────────────

  /// Classify a model-load failure.
  static String load(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('memory') ||
        msg.contains('oom') ||
        msg.contains('out of memory')) {
      return 'Not enough RAM to load this model. '
          'Try closing other apps and restarting Koshika.';
    }
    if (msg.contains('corrupt') || msg.contains('invalid')) {
      return 'Model file appears corrupted. '
          'Please delete the model and re-download it.';
    }
    if (msg.contains('gpu') || msg.contains('delegate')) {
      return 'GPU and CPU inference both failed on this device. '
          'The model may not be compatible with your hardware.';
    }
    final raw = error.toString();
    return 'Failed to load model: ${raw.length > 100 ? '${raw.substring(0, 100)}...' : raw}';
  }
}
