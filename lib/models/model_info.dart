/// Tracks the lifecycle status of the on-device AI model.
enum ModelStatus {
  /// Model files don't exist on disk.
  notDownloaded,

  /// Download is in progress.
  downloading,

  /// Model is downloaded and ready to be loaded.
  ready,

  /// Model is being loaded into memory for inference.
  loading,

  /// Model is in memory and ready for inference.
  loaded,

  /// Something went wrong (check [ModelInfo.errorMessage]).
  error,
}

/// Metadata about the on-device AI model and its current state.
class ModelInfo {
  final String name;
  final String downloadUrl;
  final int estimatedSizeMB;
  final ModelStatus status;

  /// Download progress as an integer 0–100.
  final int downloadProgress;
  final String? errorMessage;

  const ModelInfo({
    required this.name,
    required this.downloadUrl,
    required this.estimatedSizeMB,
    this.status = ModelStatus.notDownloaded,
    this.downloadProgress = 0,
    this.errorMessage,
  });

  ModelInfo copyWith({
    String? name,
    String? downloadUrl,
    int? estimatedSizeMB,
    ModelStatus? status,
    int? downloadProgress,
    String? errorMessage,
  }) {
    return ModelInfo(
      name: name ?? this.name,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      estimatedSizeMB: estimatedSizeMB ?? this.estimatedSizeMB,
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage,
    );
  }

  /// Human-readable size string.
  String get formattedSize {
    if (estimatedSizeMB >= 1000) {
      return '${(estimatedSizeMB / 1000).toStringAsFixed(1)} GB';
    }
    return '$estimatedSizeMB MB';
  }

  /// Whether the model can accept inference requests right now.
  bool get isUsable => status == ModelStatus.loaded;

  /// Whether the user can trigger a download action.
  bool get canDownload =>
      status == ModelStatus.notDownloaded || status == ModelStatus.error;

  /// Whether the user can trigger a load action.
  bool get canLoad => status == ModelStatus.ready;
}
