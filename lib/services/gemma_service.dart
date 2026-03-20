import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/model_info.dart';

/// Service managing the on-device Gemma LLM lifecycle.
///
/// Responsibilities:
/// 1. Check if model is already installed
/// 2. Download/install model with progress reporting
/// 3. Load model into memory (create active model instance)
/// 4. Generate streaming text responses via chat sessions
/// 5. Unload model to free memory
///
/// Initialized once in main.dart as a global singleton.
class GemmaService {
  // ─── Model Configuration ───────────────────────────────────────────

  /// Gemma-3 1B IT (instruction-tuned), GPU int8, MediaPipe .task format.
  /// This is a public model from litert-community — no HuggingFace token needed.
  static const String _modelName = 'Gemma 3 1B';
  static const String _modelUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int8.task';
  static const int _estimatedSizeMB = 1200;
  static const int _maxTokens = 1024;

  // ─── Health System Prompt ──────────────────────────────────────────

  static const String systemPrompt = '''
You are Koshika AI, a helpful on-device health assistant built into the Koshika app. You help users understand their lab report results.

CRITICAL RULES:
- You are NOT a doctor. Always remind users to consult a healthcare professional for medical decisions.
- Reference the user's actual lab data when it is provided in context.
- Reference specific values from the data using source numbers [1], [2], etc. when available.
- Explain biomarker values in simple, clear language a non-medical person can understand.
- Flag concerning values but avoid causing unnecessary panic.
- Suggest lifestyle factors that can influence results when appropriate.
- Be concise — aim for 3-5 sentences per response.
- Use Indian medical terminology when relevant (SGPT/ALT, TLC/WBC, etc.).
- If no lab data is provided, inform the user they need to import a lab report first.
''';

  // ─── State ─────────────────────────────────────────────────────────

  ModelInfo _modelInfo;
  InferenceModel? _activeModel;
  InferenceChat? _activeChat;
  bool _isGenerating = false;
  CancelToken? _downloadCancelToken;

  final _modelStatusController = StreamController<ModelInfo>.broadcast();

  /// Stream of model status changes — listen to reactively update UI.
  Stream<ModelInfo> get modelStatusStream => _modelStatusController.stream;

  /// Current model info snapshot.
  ModelInfo get currentModelInfo => _modelInfo;

  /// Whether a generation is currently in progress.
  bool get isGenerating => _isGenerating;

  GemmaService()
    : _modelInfo = const ModelInfo(
        name: _modelName,
        downloadUrl: _modelUrl,
        estimatedSizeMB: _estimatedSizeMB,
      );

  // ═══════════════════════════════════════════════════════════════════
  // 1. INITIALIZATION — check if model is already installed
  // ═══════════════════════════════════════════════════════════════════

  /// Check if the model is already installed on disk.
  /// Called once during app startup. Must never throw.
  Future<void> initialize() async {
    try {
      // Initialize flutter_gemma framework
      FlutterGemma.initialize(maxDownloadRetries: 5);

      // Check if the model task file is already installed
      final isInstalled = await FlutterGemma.isModelInstalled(
        _modelUrlToFilename(_modelUrl),
      );

      if (isInstalled) {
        _updateStatus(
          _modelInfo.copyWith(status: ModelStatus.ready, downloadProgress: 100),
        );
      }
      // else: stays at notDownloaded (default)
    } catch (e) {
      // Non-fatal — default to notDownloaded so the user can still try
      _updateStatus(
        _modelInfo.copyWith(
          status: ModelStatus.notDownloaded,
          errorMessage: null,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 2. DOWNLOAD & INSTALL — with progress and cancellation
  // ═══════════════════════════════════════════════════════════════════

  /// Download and install the model from the network.
  /// Progress is reported via [modelStatusStream].
  Future<void> downloadModel() async {
    // Guard: don't re-download if already downloaded, loaded, or in progress
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
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(_modelUrl)
          .withCancelToken(_downloadCancelToken!)
          .withProgress((progress) {
            _updateStatus(
              _modelInfo.copyWith(
                status: ModelStatus.downloading,
                downloadProgress: progress.clamp(0, 100),
              ),
            );
          })
          .install();

      _downloadCancelToken = null;

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

  /// Cancel an in-progress download.
  void cancelDownload() {
    _downloadCancelToken?.cancel('User cancelled download');
  }

  // ═══════════════════════════════════════════════════════════════════
  // 3. LOAD MODEL — create active model instance for inference
  // ═══════════════════════════════════════════════════════════════════

  /// Load the model into memory. Must be in [ModelStatus.ready] state.
  ///
  /// Tries GPU first for best performance, then falls back to CPU if GPU
  /// acceleration fails (common on older or low-end devices).
  Future<void> loadModel() async {
    if (_modelInfo.status != ModelStatus.ready) {
      throw StateError(
        'Cannot load model — current status is ${_modelInfo.status.name}. '
        'Model must be downloaded first.',
      );
    }

    _updateStatus(_modelInfo.copyWith(status: ModelStatus.loading));

    // Try GPU first
    try {
      _activeModel = await FlutterGemma.getActiveModel(
        maxTokens: _maxTokens,
        preferredBackend: PreferredBackend.gpu,
      );

      _updateStatus(_modelInfo.copyWith(status: ModelStatus.loaded));
      return;
    } catch (gpuError) {
      final msg = gpuError.toString().toLowerCase();
      final isGpuSpecific =
          msg.contains('gpu') ||
          msg.contains('delegate') ||
          msg.contains('accelerat') ||
          msg.contains('gl_') ||
          msg.contains('opencl') ||
          msg.contains('vulkan');

      if (!isGpuSpecific) {
        // Not a GPU-specific failure — don't retry, surface the real error
        _activeModel = null;
        _updateStatus(
          _modelInfo.copyWith(
            status: ModelStatus.error,
            errorMessage: _classifyLoadError(gpuError),
          ),
        );
        return;
      }

      // GPU failed with a GPU-specific error — fall back to CPU
    }

    // CPU fallback
    try {
      _activeModel = await FlutterGemma.getActiveModel(
        maxTokens: _maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );

      _updateStatus(_modelInfo.copyWith(status: ModelStatus.loaded));
    } catch (cpuError) {
      _activeModel = null;
      _updateStatus(
        _modelInfo.copyWith(
          status: ModelStatus.error,
          errorMessage: _classifyLoadError(cpuError),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 4. GENERATE — streaming token-by-token response
  // ═══════════════════════════════════════════════════════════════════

  /// Generate a streaming response to the user's message.
  ///
  /// [userMessage] is the raw user input.
  /// [context] is the lab data context string from [ChatContextBuilder].
  ///
  /// Yields individual text tokens as they are generated.
  /// The caller should concatenate them to build the full response.
  Stream<String> generateResponse(
    String userMessage, {
    String? context,
  }) async* {
    if (_modelInfo.status != ModelStatus.loaded || _activeModel == null) {
      yield '[Error: Model is not loaded. Please load the model first.]';
      return;
    }

    if (_isGenerating) {
      yield '[Error: Another response is still being generated.]';
      return;
    }

    _isGenerating = true;

    try {
      // Create a fresh chat session for each query.
      // We inject system prompt + context via a system message,
      // then add the user query.
      final chat = await _activeModel!.createChat();
      _activeChat = chat;

      // Build system context message
      final systemContext = StringBuffer(systemPrompt);
      if (context != null && context.isNotEmpty) {
        systemContext.writeln();
        systemContext.writeln('=== USER\'S LAB DATA ===');
        systemContext.writeln(context);
        systemContext.writeln('=== END LAB DATA ===');
      }

      // Add system info message with health context
      await chat.addQueryChunk(
        Message.systemInfo(text: systemContext.toString()),
      );

      // Add user message
      await chat.addQueryChunk(Message.text(text: userMessage, isUser: true));

      // Generate streaming response
      final responseStream = chat.generateChatResponseAsync();

      await for (final response in responseStream) {
        if (response is TextResponse) {
          yield response.token;
        }
        // We ignore FunctionCallResponse and ThinkingResponse for MVP
      }

      // Clean up this chat session
      _activeChat = null;
    } catch (e) {
      final errorMsg = e.toString();
      final truncated = errorMsg.length > 150
          ? '${errorMsg.substring(0, 150)}...'
          : errorMsg;
      yield '\n\n[Generation error: $truncated]';

      // Try to clean up
      try {
        await _activeChat?.stopGeneration();
      } catch (_) {}
      _activeChat = null;
    } finally {
      _isGenerating = false;
    }
  }

  /// Stop the current generation.
  Future<void> stopGeneration() async {
    try {
      await _activeChat?.stopGeneration();
    } catch (_) {}
    _isGenerating = false;
  }

  // ═══════════════════════════════════════════════════════════════════
  // 5. UNLOAD — free memory
  // ═══════════════════════════════════════════════════════════════════

  /// Unload the model from memory. The model files stay on disk.
  Future<void> unloadModel() async {
    try {
      // Stop any in-progress generation before unloading
      if (_isGenerating) {
        await stopGeneration();
      }
      _activeChat = null;
      await _activeModel?.close();
      _activeModel = null;

      _updateStatus(_modelInfo.copyWith(status: ModelStatus.ready));
    } catch (e) {
      // Best-effort cleanup; still mark as ready since files exist on disk
      _activeModel = null;
      _activeChat = null;
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

  /// Extract the filename from the model URL for isModelInstalled check.
  String _modelUrlToFilename(String url) {
    final uri = Uri.parse(url);
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url;
  }

  String _classifyDownloadError(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('socket') || msg.contains('connection')) {
      return 'Network error. Please check your internet connection and try again.';
    }
    if (msg.contains('storage') ||
        msg.contains('space') ||
        msg.contains('no space')) {
      return 'Insufficient storage. The model requires ~${_estimatedSizeMB}MB of free space.';
    }
    if (msg.contains('timeout')) {
      return 'Download timed out. Please try again on a stable connection.';
    }
    if (msg.contains('403') || msg.contains('forbidden')) {
      return 'Access denied. This model may require a HuggingFace token.';
    }
    if (msg.contains('404') || msg.contains('not found')) {
      return 'Model file not found at the download URL. It may have been moved or removed.';
    }
    return 'Download failed: ${error.toString().length > 100 ? '${error.toString().substring(0, 100)}...' : error}';
  }

  String _classifyLoadError(dynamic error) {
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
    return 'Failed to load model: ${error.toString().length > 100 ? '${error.toString().substring(0, 100)}...' : error}';
  }

  /// Release all resources. Call when the app is shutting down.
  void dispose() {
    _activeChat = null;
    final model = _activeModel;
    _activeModel = null;
    model?.close();
    _modelStatusController.close();
  }
}
