import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_info.dart';

/// Service managing the on-device EmbeddingGemma model lifecycle.
///
/// Responsibilities:
/// 1. Check if embedding model is already installed
/// 2. Download/install model + tokenizer with progress reporting
/// 3. Load model into memory (create active embedder instance)
/// 4. Generate text embeddings (single or batch)
/// 5. Unload model to free memory
///
/// Requires a HuggingFace token for download (gated model).
class EmbeddingService {
  // ─── Model Configuration ───────────────────────────────────────────

  static const String _modelName = 'EmbeddingGemma 300M';

  /// 4-bit quantized variant — 75MB download, 768-dim output.
  /// Smallest variant that still produces high-quality embeddings.
  static const String _modelUrl =
      'https://huggingface.co/google/embeddinggemma-300m-4bit/resolve/main/model.tflite';
  static const String _tokenizerUrl =
      'https://huggingface.co/google/embeddinggemma-300m-4bit/resolve/main/sentencepiece.model';

  /// iOS needs a JSON tokenizer (sentencepiece.model conflicts with TFLite on iOS).
  static const String _iosTokenizerUrl =
      'https://github.com/nicholasgasior/embeddinggemma-tokenizer/releases/download/v1/tokenizer.json';

  static const int _estimatedSizeMB = 75;
  static const String _hfTokenKey = 'koshika_hf_token';

  // ─── State ─────────────────────────────────────────────────────────

  ModelInfo _modelInfo;
  EmbeddingModel? _embedder;
  CancelToken? _downloadCancelToken;

  final _modelStatusController = StreamController<ModelInfo>.broadcast();

  Stream<ModelInfo> get modelStatusStream => _modelStatusController.stream;
  ModelInfo get currentModelInfo => _modelInfo;
  bool get isLoaded => _embedder != null;
  bool get isInstalled =>
      _modelInfo.status == ModelStatus.ready ||
      _modelInfo.status == ModelStatus.loaded ||
      _modelInfo.status == ModelStatus.loading;

  EmbeddingService()
    : _modelInfo = const ModelInfo(
        name: _modelName,
        downloadUrl: _modelUrl,
        estimatedSizeMB: _estimatedSizeMB,
      );

  // ═══════════════════════════════════════════════════════════════════
  // 1. INITIALIZATION — check if model is already installed
  // ═══════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    try {
      final hasEmbedder = FlutterGemma.hasActiveEmbedder();
      if (hasEmbedder) {
        _updateStatus(
          _modelInfo.copyWith(status: ModelStatus.ready, downloadProgress: 100),
        );
      }
    } catch (e) {
      debugPrint('EmbeddingService.initialize: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 2. DOWNLOAD & INSTALL — requires HuggingFace token
  // ═══════════════════════════════════════════════════════════════════

  /// Save HuggingFace token for future use.
  static Future<void> saveHfToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hfTokenKey, token);
  }

  /// Retrieve stored HuggingFace token.
  static Future<String?> getHfToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hfTokenKey);
  }

  /// Download and install the embedding model + tokenizer.
  Future<void> downloadModel({required String hfToken}) async {
    if (_modelInfo.status == ModelStatus.downloading ||
        _modelInfo.status == ModelStatus.ready ||
        _modelInfo.status == ModelStatus.loaded ||
        _modelInfo.status == ModelStatus.loading) {
      return;
    }

    _updateStatus(
      _modelInfo.copyWith(
        status: ModelStatus.downloading,
        downloadProgress: 0,
        errorMessage: null,
      ),
    );

    _downloadCancelToken = CancelToken();

    try {
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(_modelUrl, token: hfToken)
          .tokenizerFromNetwork(
            _tokenizerUrl,
            token: hfToken,
            iosPath: _iosTokenizerUrl,
          )
          .withCancelToken(_downloadCancelToken!)
          .withModelProgress((progress) {
            _updateStatus(
              _modelInfo.copyWith(
                status: ModelStatus.downloading,
                downloadProgress: progress.clamp(0, 100),
              ),
            );
          })
          .install();

      _downloadCancelToken = null;

      // Save token for future use
      await saveHfToken(hfToken);

      _updateStatus(
        _modelInfo.copyWith(status: ModelStatus.ready, downloadProgress: 100),
      );
    } catch (e) {
      _downloadCancelToken = null;

      if (CancelToken.isCancel(e)) {
        _updateStatus(
          _modelInfo.copyWith(
            status: ModelStatus.notDownloaded,
            downloadProgress: 0,
            errorMessage: null,
          ),
        );
        return;
      }

      _updateStatus(
        _modelInfo.copyWith(
          status: ModelStatus.error,
          downloadProgress: 0,
          errorMessage: _classifyDownloadError(e),
        ),
      );
    }
  }

  void cancelDownload() {
    _downloadCancelToken?.cancel('User cancelled download');
  }

  // ═══════════════════════════════════════════════════════════════════
  // 3. LOAD MODEL — create active embedder instance
  // ═══════════════════════════════════════════════════════════════════

  Future<void> loadModel() async {
    if (_modelInfo.status != ModelStatus.ready) {
      throw StateError(
        'Cannot load embedder — current status is ${_modelInfo.status.name}. '
        'Model must be downloaded first.',
      );
    }

    _updateStatus(_modelInfo.copyWith(status: ModelStatus.loading));

    try {
      _embedder = await FlutterGemma.getActiveEmbedder(
        preferredBackend: PreferredBackend.gpu,
      );
      _updateStatus(_modelInfo.copyWith(status: ModelStatus.loaded));
    } catch (gpuError) {
      // Try CPU fallback
      try {
        _embedder = await FlutterGemma.getActiveEmbedder(
          preferredBackend: PreferredBackend.cpu,
        );
        _updateStatus(_modelInfo.copyWith(status: ModelStatus.loaded));
      } catch (cpuError) {
        _embedder = null;
        _updateStatus(
          _modelInfo.copyWith(
            status: ModelStatus.error,
            errorMessage:
                'Failed to load embedding model: ${cpuError.toString().length > 100 ? '${cpuError.toString().substring(0, 100)}...' : cpuError}',
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 4. EMBED — generate embedding vectors
  // ═══════════════════════════════════════════════════════════════════

  /// Embed a single text into a 768-dim vector.
  Future<List<double>> embed(String text) async {
    if (_embedder == null) throw StateError('Embedder not loaded');
    return _embedder!.generateEmbedding(text);
  }

  /// Batch embed multiple texts.
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (_embedder == null) throw StateError('Embedder not loaded');
    return _embedder!.generateEmbeddings(texts);
  }

  // ═══════════════════════════════════════════════════════════════════
  // 5. UNLOAD — free memory
  // ═══════════════════════════════════════════════════════════════════

  Future<void> unloadModel() async {
    try {
      await _embedder?.close();
      _embedder = null;
      _updateStatus(_modelInfo.copyWith(status: ModelStatus.ready));
    } catch (e) {
      _embedder = null;
      _updateStatus(_modelInfo.copyWith(status: ModelStatus.ready));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════

  void _updateStatus(ModelInfo info) {
    _modelInfo = info;
    if (!_modelStatusController.isClosed) {
      _modelStatusController.add(info);
    }
  }

  String _classifyDownloadError(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('socket') || msg.contains('connection')) {
      return 'Network error. Check your internet connection.';
    }
    if (msg.contains('storage') || msg.contains('space')) {
      return 'Insufficient storage. The model requires ~${_estimatedSizeMB}MB.';
    }
    if (msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('forbidden')) {
      return 'Access denied. Check your HuggingFace token and model access.';
    }
    if (msg.contains('404') || msg.contains('not found')) {
      return 'Model not found at the download URL.';
    }
    return 'Download failed: ${error.toString().length > 100 ? '${error.toString().substring(0, 100)}...' : error}';
  }

  void dispose() {
    _embedder?.close();
    _embedder = null;
    _modelStatusController.close();
  }
}
