import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import '../models/llm_model_config.dart';
import '../models/model_info.dart';
import '../utils/error_classifier.dart';
import 'model_downloader.dart';

/// Service managing the on-device bge-small-en-v1.5 embedding model.
///
/// Uses llamadart's embedding mode to produce 384-dimensional vectors
/// for ObjectBox HNSW search.
class LlmEmbeddingService {
  static final LlmModelConfig _config = LlmModelRegistry.embeddingModel;

  // ─── State ───────────────────────────────────────────────────────────

  ModelInfo _modelInfo;
  LlamaEngine? _engine;
  ModelDownloader? _downloader;

  final _statusController = StreamController<ModelInfo>.broadcast();

  Stream<ModelInfo> get modelStatusStream => _statusController.stream;
  ModelInfo get currentModelInfo => _modelInfo;
  bool get isLoaded => _engine != null && _engine!.isReady;
  bool get isInstalled =>
      _modelInfo.status == ModelStatus.ready ||
      _modelInfo.status == ModelStatus.loaded ||
      _modelInfo.status == ModelStatus.loading;

  LlmEmbeddingService()
    : _modelInfo = ModelInfo(
        name: _config.name,
        downloadUrl: _config.downloadUrl,
        estimatedSizeMB: _config.estimatedSizeMB,
      );

  // ═══════════════════════════════════════════════════════════════════════
  // 1. INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if the embedding model is already downloaded.
  Future<void> initialize() async {
    try {
      final downloaded = await ModelDownloader.isDownloaded(_config.filename);
      if (downloaded) {
        _updateStatus(
          _modelInfo.copyWith(status: ModelStatus.ready, downloadProgress: 100),
        );
      }
    } catch (e) {
      debugPrint('LlmEmbeddingService.initialize: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. DOWNLOAD — no HF token needed (public model)
  // ═══════════════════════════════════════════════════════════════════════

  /// Download the embedding model GGUF.
  Future<void> downloadModel() async {
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

    _downloader = ModelDownloader();

    try {
      await _downloader!.download(
        _config.downloadUrl,
        _config.filename,
        onProgress: (received, total) {
          final pct = total > 0 ? (received * 100 ~/ total) : 0;
          _updateStatus(
            _modelInfo.copyWith(
              status: ModelStatus.downloading,
              downloadProgress: pct.clamp(0, 100),
            ),
          );
        },
      );

      _downloader = null;
      _updateStatus(
        _modelInfo.copyWith(status: ModelStatus.ready, downloadProgress: 100),
      );
    } catch (e) {
      _downloader = null;

      if (e is DownloadCancelledException) {
        _updateStatus(
          _modelInfo.copyWith(
            status: ModelStatus.notDownloaded,
            downloadProgress: 0,
          ),
        );
        return;
      }

      _updateStatus(
        _modelInfo.copyWith(
          status: ModelStatus.error,
          downloadProgress: 0,
          errorMessage: ErrorClassifier.download(
            e,
            estimatedSizeMB: _config.estimatedSizeMB,
          ),
        ),
      );
    }
  }

  void cancelDownload() {
    _downloader?.cancel();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. LOAD
  // ═══════════════════════════════════════════════════════════════════════

  /// Load the embedding model into memory.
  Future<void> loadModel() async {
    if (_modelInfo.status != ModelStatus.ready) {
      throw StateError(
        'Cannot load embedder — current status is ${_modelInfo.status.name}. '
        'Model must be downloaded first.',
      );
    }

    _updateStatus(_modelInfo.copyWith(status: ModelStatus.loading));

    try {
      final path = await ModelDownloader.getModelPath(_config.filename);
      _engine = LlamaEngine(LlamaBackend());
      await _engine!.loadModel(path);
      _updateStatus(_modelInfo.copyWith(status: ModelStatus.loaded));
    } catch (e) {
      await _engine?.dispose();
      _engine = null;
      _updateStatus(
        _modelInfo.copyWith(
          status: ModelStatus.error,
          errorMessage: ErrorClassifier.load(e),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. EMBED — generate embedding vectors
  // ═══════════════════════════════════════════════════════════════════════

  /// Embed a single text into a 384-dim vector.
  Future<List<double>> embed(String text) async {
    if (_engine == null || !_engine!.isReady) {
      throw StateError('Embedder not loaded');
    }
    return _engine!.embed(text, normalize: true);
  }

  /// Batch embed multiple texts.
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (_engine == null || !_engine!.isReady) {
      throw StateError('Embedder not loaded');
    }
    return _engine!.embedBatch(texts, normalize: true);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. UNLOAD
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> unloadModel() async {
    if (_engine != null) {
      await _engine!.unloadModel();
    }
    if (_modelInfo.status == ModelStatus.loaded ||
        _modelInfo.status == ModelStatus.loading) {
      _updateStatus(_modelInfo.copyWith(status: ModelStatus.ready));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  void _updateStatus(ModelInfo info) {
    _modelInfo = info;
    if (!_statusController.isClosed) _statusController.add(info);
  }

  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
    _statusController.close();
  }
}
