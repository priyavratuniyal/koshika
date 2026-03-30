class CustomModelUrlDetails {
  final String normalizedUrl;
  final String filename;

  const CustomModelUrlDetails({
    required this.normalizedUrl,
    required this.filename,
  });

  String get suggestedName =>
      filename.replaceFirst(RegExp(r'\.gguf$', caseSensitive: false), '');
}

String? _extractGgufFilename(Uri uri) {
  if (uri.pathSegments.isNotEmpty) {
    final candidate = uri.pathSegments.last;
    if (candidate.isNotEmpty && candidate.toLowerCase().endsWith('.gguf')) {
      return candidate;
    }
  }

  for (final values in uri.queryParametersAll.values) {
    for (final value in values) {
      final candidate = _extractGgufFilenameFromValue(value);
      if (candidate != null) return candidate;
    }
  }

  return null;
}

String? _extractGgufFilenameFromValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  final candidate = uri != null && uri.pathSegments.isNotEmpty
      ? uri.pathSegments.last
      : trimmed.split('/').last;

  if (candidate.isEmpty || !candidate.toLowerCase().endsWith('.gguf')) {
    return null;
  }

  return candidate;
}

String _filenameFromDownloadUrl(
  String downloadUrl, {
  required String fallbackId,
}) {
  final uri = Uri.tryParse(downloadUrl);
  if (uri == null) return '$fallbackId.gguf';
  return _extractGgufFilename(uri) ?? '$fallbackId.gguf';
}

/// Configuration for a downloadable GGUF model (curated or custom).
class LlmModelConfig {
  final String id;
  final String name;
  final String downloadUrl;
  final int estimatedSizeMB;
  final String description;
  final bool isCustom;

  const LlmModelConfig({
    required this.id,
    required this.name,
    required this.downloadUrl,
    required this.estimatedSizeMB,
    required this.description,
    this.isCustom = false,
  });

  /// Derive the on-disk filename from the download URL.
  String get filename {
    return _filenameFromDownloadUrl(downloadUrl, fallbackId: id);
  }

  /// Human-readable size string.
  String get formattedSize {
    if (estimatedSizeMB == 0) return 'Unknown';
    if (estimatedSizeMB >= 1000) {
      return '${(estimatedSizeMB / 1000).toStringAsFixed(1)} GB';
    }
    return '~$estimatedSizeMB MB';
  }
}

/// Registry of curated chat models + factory for custom GGUF URLs.
abstract final class LlmModelRegistry {
  static const defaultModelId = 'qwen3-0.6b';

  static const List<LlmModelConfig> curated = [
    LlmModelConfig(
      id: 'smollm2-360m',
      name: 'SmolLM2 360M',
      downloadUrl:
          'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf',
      estimatedSizeMB: 230,
      description: 'Smallest, fastest load, lowest RAM',
    ),
    LlmModelConfig(
      id: 'qwen3-0.6b',
      name: 'Qwen3 0.6B',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf',
      estimatedSizeMB: 639,
      description: 'Balanced quality and size',
    ),
    LlmModelConfig(
      id: 'llama3.2-1b',
      name: 'Llama 3.2 1B',
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      estimatedSizeMB: 770,
      description: 'Strong instruction following',
    ),
    LlmModelConfig(
      id: 'gemma3-1b',
      name: 'Gemma 3 1B',
      downloadUrl:
          'https://huggingface.co/google/gemma-3-1b-it-qat-q4_0-gguf/resolve/main/gemma-3-1b-it-q4_0.gguf',
      estimatedSizeMB: 1000,
      description: 'Most capable curated model',
    ),
  ];

  /// Embedding model — fixed, not user-selectable.
  static const embeddingModel = LlmModelConfig(
    id: 'bge-small-en',
    name: 'bge-small-en-v1.5',
    downloadUrl:
        'https://huggingface.co/CompendiumLabs/bge-small-en-v1.5-gguf/resolve/main/bge-small-en-v1.5-q8_0.gguf',
    estimatedSizeMB: 67,
    description: 'Semantic search model',
  );

  /// Create a config for a user-provided GGUF URL.
  static LlmModelConfig custom({
    required String name,
    required String downloadUrl,
  }) {
    final parsed = inspectCustomDownloadUrl(downloadUrl);
    final displayName = name.trim().isNotEmpty
        ? name.trim()
        : parsed.suggestedName;

    return LlmModelConfig(
      id: 'custom',
      name: displayName,
      downloadUrl: parsed.normalizedUrl,
      estimatedSizeMB: 0,
      description: 'Custom GGUF model',
      isCustom: true,
    );
  }

  static CustomModelUrlDetails inspectCustomDownloadUrl(String rawUrl) {
    final normalizedUrl = rawUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw ArgumentError('URL is required');
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw ArgumentError('URL must be a valid HTTPS link');
    }

    final filename = _extractGgufFilename(uri);
    if (filename == null) {
      throw ArgumentError('URL must point to a .gguf file');
    }

    return CustomModelUrlDetails(
      normalizedUrl: normalizedUrl,
      filename: filename,
    );
  }

  /// Look up a curated model by id. Returns null for unknown ids.
  static LlmModelConfig? findById(String id) {
    for (final m in curated) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The default curated model.
  static LlmModelConfig get defaultModel =>
      findById(defaultModelId) ?? curated.first;
}
