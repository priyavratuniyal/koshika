import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/ai_prompts.dart';
import '../models/llm_model_config.dart';
import '../models/model_info.dart';
import '../utils/error_classifier.dart';
import 'model_downloader.dart';

/// Service managing an on-device GGUF chat model via llama.cpp.
///
/// Model-agnostic — takes an [LlmModelConfig] and works identically for
/// curated or custom GGUF models.
///
/// State machine:
///   notDownloaded → downloading → ready → loading → loaded
///   Any state may transition to error.
class LlmService {
  // ─── Persistence keys ────────────────────────────────────────────────

  static const _selectedModelKey = 'koshika_selected_model_id';
  static const _customNameKey = 'koshika_custom_model_name';
  static const _customUrlKey = 'koshika_custom_model_url';

  // ─── State ───────────────────────────────────────────────────────────

  LlmModelConfig _config;
  ModelInfo _modelInfo;
  LlamaEngine? _engine;
  ModelDownloader? _downloader;
  bool _isGenerating = false;

  final _statusController = StreamController<ModelInfo>.broadcast();

  /// Stream of model status changes — drive UI updates from here.
  Stream<ModelInfo> get modelStatusStream => _statusController.stream;

  /// Current model info snapshot.
  ModelInfo get currentModelInfo => _modelInfo;

  /// The currently selected model configuration.
  LlmModelConfig get currentConfig => _config;

  /// Whether a generation is in progress.
  bool get isGenerating => _isGenerating;

  static String get systemPrompt => AiPrompts.systemPrompt;

  LlmService(this._config)
    : _modelInfo = ModelInfo(
        name: _config.name,
        downloadUrl: _config.downloadUrl,
        estimatedSizeMB: _config.estimatedSizeMB,
      );

  // ═══════════════════════════════════════════════════════════════════════
  // 1. INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Restore saved model selection and check if the file exists on disk.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_selectedModelKey);

      if (savedId != null) {
        LlmModelConfig? restored;
        if (savedId == 'custom') {
          final name = prefs.getString(_customNameKey);
          final url = prefs.getString(_customUrlKey);
          if (name != null && url != null) {
            restored = LlmModelRegistry.custom(name: name, downloadUrl: url);
          }
        } else {
          restored = LlmModelRegistry.findById(savedId);
        }
        if (restored != null) _config = restored;
      }

      final downloaded = await ModelDownloader.isDownloaded(_config.filename);
      _updateStatus(
        ModelInfo(
          name: _config.name,
          downloadUrl: _config.downloadUrl,
          estimatedSizeMB: _config.estimatedSizeMB,
          status: downloaded ? ModelStatus.ready : ModelStatus.notDownloaded,
          downloadProgress: downloaded ? 100 : 0,
        ),
      );
    } catch (e) {
      debugPrint('LlmService.initialize: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. MODEL SELECTION
  // ═══════════════════════════════════════════════════════════════════════

  /// Switch to a different model. Unloads + deletes the current file first.
  Future<void> switchModel(LlmModelConfig newConfig) async {
    if (newConfig.id == _config.id && !newConfig.isCustom) return;

    // Tear down current model
    await unloadModel();
    try {
      await ModelDownloader.deleteModel(_config.filename);
    } catch (_) {}

    _config = newConfig;

    // Persist selection
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, newConfig.id);
    if (newConfig.isCustom) {
      await prefs.setString(_customNameKey, newConfig.name);
      await prefs.setString(_customUrlKey, newConfig.downloadUrl);
    }

    _updateStatus(
      ModelInfo(
        name: newConfig.name,
        downloadUrl: newConfig.downloadUrl,
        estimatedSizeMB: newConfig.estimatedSizeMB,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. DOWNLOAD
  // ═══════════════════════════════════════════════════════════════════════

  /// Download the currently selected model. Public, no HF token needed.
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

  /// Cancel an in-progress download.
  void cancelDownload() {
    _downloader?.cancel();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. LOAD MODEL
  // ═══════════════════════════════════════════════════════════════════════

  /// Load the downloaded GGUF into memory.
  Future<void> loadModel() async {
    if (_modelInfo.status != ModelStatus.ready) {
      throw StateError(
        'Cannot load model — current status is ${_modelInfo.status.name}. '
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
  // 5. GENERATE — streaming token-by-token response
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate a streaming response.
  ///
  /// [userMessage] is the raw user input.
  /// [context] is the lab data context from [ChatContextBuilder].
  /// Yields individual text tokens for the UI to concatenate.
  Stream<String> generateResponse(
    String userMessage, {
    String? context,
  }) async* {
    if (_modelInfo.status != ModelStatus.loaded || _engine == null) {
      yield '[Error: Model is not loaded. Please load the model first.]';
      return;
    }

    if (_isGenerating) {
      yield '[Error: Another response is still being generated.]';
      return;
    }

    _isGenerating = true;

    try {
      final prompt = _formatPrompt(userMessage, context);

      await for (final token in _engine!.generate(prompt)) {
        if (!_isGenerating) break; // stopped by user
        yield token;
      }
    } catch (e) {
      final msg = e.toString();
      final truncated = msg.length > 150 ? '${msg.substring(0, 150)}...' : msg;
      yield '\n\n[Generation error: $truncated]';
    } finally {
      _isGenerating = false;
    }
  }

  /// Stop the current generation.
  Future<void> stopGeneration() async {
    _isGenerating = false;
    _engine?.cancelGeneration();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 6. UNLOAD — free memory
  // ═══════════════════════════════════════════════════════════════════════

  /// Unload the model from memory. Files stay on disk.
  Future<void> unloadModel() async {
    if (_isGenerating) await stopGeneration();
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

  /// Format the full prompt in ChatML template.
  ///
  /// ChatML is widely supported by instruction-tuned GGUF models
  /// (Qwen, SmolLM, Llama-3, and even Gemma in most quantizations).
  String _formatPrompt(String userMessage, String? context) {
    final buf = StringBuffer();

    // System turn
    buf.writeln('<|im_start|>system');
    buf.writeln(systemPrompt);
    buf.writeln('<|im_end|>');

    // User turn — include lab data context inline so small models see it
    buf.writeln('<|im_start|>user');
    if (context != null && context.isNotEmpty) {
      buf.writeln('My lab data:');
      buf.writeln(context);
      buf.writeln();
      buf.writeln('Question: $userMessage');
    } else {
      buf.writeln(userMessage);
    }
    buf.writeln('<|im_end|>');

    // Assistant turn — model completes from here
    buf.write('<|im_start|>assistant\n');

    return buf.toString();
  }

  void _updateStatus(ModelInfo info) {
    _modelInfo = info;
    if (!_statusController.isClosed) _statusController.add(info);
  }

  /// Release all resources.
  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
    _statusController.close();
  }
}
