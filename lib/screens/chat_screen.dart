import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../models/retrieval_result.dart';
import '../constants/ai_prompts.dart';
import '../constants/llm_strings.dart';
import '../constants/token_budgets.dart';
import '../constants/validation_strings.dart';
import '../models/query_decision.dart';
import '../services/chat_context_builder.dart';
import '../services/citation_extractor.dart';
import '../services/intent_classifier.dart';
import '../services/llm_service.dart';
import '../services/output_validator.dart';
import '../services/query_router.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';
import '../widgets/chat_message_bubble.dart';

/// The AI Chat screen — transforms from download/load prompt into a
/// full streaming chat interface depending on the model status.
///
/// States:
///   1. notDownloaded → download prompt with size info
///   2. downloading   → progress bar with cancel option
///   3. ready         → "Load Model" button
///   4. loading       → loading spinner
///   5. loaded        → full chat UI with streaming responses
///   6. error         → error message with retry button
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _SessionSheetAction { newChat }

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final ChatContextBuilder _contextBuilder;
  late final QueryRouter _queryRouter;
  IntentClassifier? _intentClassifier;
  ChatSession? _currentSession;
  bool _hasShownPersistenceWarning = false;
  bool _hasLoggedUnknownRoleIndex = false;

  StreamSubscription<ModelInfo>? _statusSubscription;
  StreamSubscription<String>? _generationSubscription;
  ModelInfo _modelInfo = llmService.currentModelInfo;

  @override
  void initState() {
    super.initState();
    _contextBuilder = ChatContextBuilder(vectorStore: vectorStoreService);
    _initIntentClassifier();
    _queryRouter = QueryRouter(classifier: _intentClassifier);
    _statusSubscription = llmService.modelStatusStream.listen((info) {
      if (mounted) {
        setState(() => _modelInfo = info);
      }
    });
    // Auto-load model if already downloaded
    if (_modelInfo.status == ModelStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadModel());
    }
  }

  void _initIntentClassifier() {
    if (!embeddingService.isLoaded) return;
    _intentClassifier = IntentClassifier(embeddingService);
    // Initialize centroids in the background — non-blocking
    _intentClassifier!.initialize();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _generationSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ChatRole _roleFromIndex(int index) {
    if (index >= 0 && index < ChatRole.values.length) {
      return ChatRole.values[index];
    }
    if (!_hasLoggedUnknownRoleIndex) {
      _hasLoggedUnknownRoleIndex = true;
      debugPrint(
        'Chat persistence warning: unknown roleIndex=$index. '
        'Falling back to assistant role.',
      );
    }
    return ChatRole.assistant;
  }

  ChatSession? _ensureCurrentSession(String firstMessage) {
    final existing = _currentSession;
    if (existing != null) return existing;
    try {
      final created = objectbox.createSession(firstMessage);
      _currentSession = created;
      return created;
    } catch (e, st) {
      _reportStorageError('create chat session', e, st);
      return null;
    }
  }

  void _logStorageError(String action, Object error, [StackTrace? st]) {
    debugPrint('Chat persistence error during $action: $error');
    if (st != null) {
      debugPrint(st.toString());
    }
  }

  void _reportStorageError(String action, Object error, [StackTrace? st]) {
    _logStorageError(action, error, st);
    if (!mounted || _hasShownPersistenceWarning) return;
    _hasShownPersistenceWarning = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(LlmStrings.persistenceWarning)),
    );
  }

  bool _persistMessage(ChatSession session, ChatMessage message) {
    try {
      objectbox.saveMessage(
        session,
        PersistedChatMessage(
          content: message.content,
          roleIndex: message.role.index,
          timestamp: message.timestamp,
          isError: message.isError,
        ),
      );
      return true;
    } catch (e, st) {
      _reportStorageError('save chat message', e, st);
      return false;
    }
  }

  Future<void> _openSessionSheet() async {
    if (!mounted) return;
    List<ChatSession> sessions;
    try {
      sessions = objectbox.getAllSessions();
    } catch (e, st) {
      _reportStorageError('open session list', e, st);
      return;
    }

    final result = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final currentId = _currentSession?.id;

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.add_comment_outlined),
                  title: const Text('New chat'),
                  onTap: () =>
                      Navigator.of(context).pop(_SessionSheetAction.newChat),
                ),
                const SizedBox(height: KoshikaSpacing.xs),
                Expanded(
                  child: sessions.isEmpty
                      ? const Center(child: Text('No previous conversations'))
                      : ListView.builder(
                          itemCount: sessions.length,
                          itemBuilder: (context, index) {
                            final session = sessions[index];
                            final isCurrent = session.id == currentId;
                            return ListTile(
                              leading: Icon(
                                isCurrent
                                    ? Icons.chat_bubble
                                    : Icons.chat_bubble_outline,
                              ),
                              title: Text(
                                session.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Updated ${session.lastMessageAt.day}/${session.lastMessageAt.month}/${session.lastMessageAt.year}',
                              ),
                              trailing: isCurrent
                                  ? Icon(
                                      Icons.check,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : null,
                              onTap: () => Navigator.of(context).pop(session),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (result == _SessionSheetAction.newChat) {
      _startNewChat();
      return;
    }
    if (result is ChatSession) {
      await _loadSession(result);
    }
  }

  Future<void> _loadSession(ChatSession session) async {
    _generationSubscription?.cancel();
    _generationSubscription = null;
    await llmService.stopGeneration();

    List<PersistedChatMessage> persisted;
    try {
      persisted = objectbox.getMessagesForSession(session.id);
    } catch (e, st) {
      _reportStorageError('load selected session', e, st);
      return;
    }
    if (!mounted) return;

    setState(() {
      _currentSession = session;
      _messages
        ..clear()
        ..addAll(
          persisted.map(
            (m) => ChatMessage(
              id: 'db-${m.id}',
              content: m.content,
              role: _roleFromIndex(m.roleIndex),
              timestamp: m.timestamp,
              isStreaming: false,
              isError: m.isError,
            ),
          ),
        );
    });
    _scrollToBottom();
  }

  // ─── Chat Logic ────────────────────────────────────────────────────

  /// Extract up to 2 prior turns (1 user + 1 assistant) from the current
  /// message list for conversation history injection.
  ///
  /// Returns null if there are fewer than 2 prior messages.
  /// History content is truncated to [TokenBudgets.maxHistoryChars] to
  /// stay within the context budget.
  List<ChatHistoryTurn>? _buildConversationHistory() {
    // Need at least 2 prior messages (user + assistant) before the current one
    // The current user message is already added, so look at messages before it
    if (_messages.length < 3) return null;

    final history = <ChatHistoryTurn>[];
    // Walk backwards from the message before the current user message
    // (which is the last message in the list)
    final startIndex = _messages.length - 2; // skip current user message
    int charsUsed = 0;

    for (int i = startIndex; i >= 0 && history.length < 2; i--) {
      final msg = _messages[i];
      if (msg.isError || msg.isStreaming) continue;
      if (msg.role != ChatRole.user && msg.role != ChatRole.assistant) continue;

      final content = msg.content;
      if (charsUsed + content.length > TokenBudgets.maxHistoryChars) break;

      history.insert(
        0,
        ChatHistoryTurn(content: content, isUser: msg.role == ChatRole.user),
      );
      charsUsed += content.length;
    }

    return history.isEmpty ? null : history;
  }

  /// Display a pre-built response without invoking the LLM.
  void _addDeterministicResponse(String content, {ChatSession? session}) {
    final msg = ChatMessage(content: content, role: ChatRole.assistant);
    setState(() => _messages.add(msg));
    if (session != null) _persistMessage(session, msg);
    _scrollToBottom();
  }

  Future<void> _sendMessage([String? overrideText]) async {
    final text = (overrideText ?? _textController.text).trim();
    if (text.isEmpty || !mounted) return;
    if (llmService.isGenerating) return;

    _textController.clear();
    final activeSession = _ensureCurrentSession(text);

    // Add user message
    final userMsg = ChatMessage.user(text);
    setState(() {
      _messages.add(userMsg);
    });
    if (activeSession != null) {
      _persistMessage(activeSession, userMsg);
    }
    _scrollToBottom();

    // Collect conversation history before routing — used for both
    // history-aware routing and prompt injection.
    final history = _buildConversationHistory();

    // Route the query — may short-circuit with a deterministic response
    late final QueryRouteResult routeResult;
    try {
      final hasLabData = objectbox.getLatestResults().isNotEmpty;
      routeResult = await _queryRouter.route(
        text,
        hasLabData: hasLabData,
        conversationHistory: history,
      );
    } catch (e) {
      // If routing fails (e.g. ObjectBox error), fall through to LLM
      debugPrint('${LlmStrings.routingFailedLog}$e');
      routeResult = const QueryRouteResult(
        decision: QueryDecision.answerGeneralHealth,
      );
    }

    if (!routeResult.requiresLlm) {
      if (mounted) {
        _addDeterministicResponse(
          routeResult.deterministicResponse!,
          session: activeSession,
        );
      }
      return;
    }

    // Select system prompt and context strategy based on routing decision
    final isGeneralHealth =
        routeResult.decision == QueryDecision.answerGeneralHealth;
    final promptOverride = isGeneralHealth
        ? AiPrompts.generalHealthPrompt
        : null;

    // Only build lab context for queries that need it — skip semantic search
    // for general health education to avoid contradictory prompt/context
    // signals and save computation.
    String? context;
    var retrievedDocs = <RetrievalResult>[];
    if (!isGeneralHealth) {
      context = await _contextBuilder.buildQueryContext(text);
      retrievedDocs = List<RetrievalResult>.from(
        _contextBuilder.lastRetrievedDocs,
      );
    }

    if (!mounted) return;

    // Add placeholder assistant message (streaming)
    final assistantMsg = ChatMessage.assistantStreaming();
    setState(() {
      _messages.add(assistantMsg);
    });
    _scrollToBottom();

    _startGeneration(
      query: text,
      context: context,
      promptOverride: promptOverride,
      history: history,
      retrievedDocs: retrievedDocs,
      activeSession: activeSession,
      assistantIndex: _messages.length - 1,
    );
  }

  /// Start streaming generation with retry support.
  ///
  /// On empty output or generation error, retries up to
  /// [TokenBudgets.maxGenerationRetries] times before showing a fallback.
  void _startGeneration({
    required String query,
    required String? context,
    required String? promptOverride,
    required List<ChatHistoryTurn>? history,
    required List<RetrievalResult> retrievedDocs,
    required ChatSession? activeSession,
    required int assistantIndex,
    int attempt = 0,
  }) {
    final tokenBuffer = StringBuffer();
    var persistAttempted = false;

    void persistAssistantOnce() {
      final session = activeSession;
      if (session == null || persistAttempted) return;
      persistAttempted = true;
      _persistMessage(session, _messages[assistantIndex]);
    }

    _generationSubscription?.cancel();
    _generationSubscription = llmService
        .generateResponse(
          query,
          context: context,
          systemPromptOverride: promptOverride,
          conversationHistory: history,
        )
        .listen(
          (token) {
            tokenBuffer.write(token);
            if (mounted) {
              setState(() {
                _messages[assistantIndex] = _messages[assistantIndex].copyWith(
                  content: tokenBuffer.toString(),
                  isStreaming: true,
                );
              });
              _scrollToBottom();
            }
          },
          onDone: () {
            if (!mounted) return;
            var finalContent = tokenBuffer.toString();

            // Validate output before showing to user
            final validation = OutputValidator.validate(
              finalContent,
              labContext: context,
            );

            // Retry on empty or garbled output (up to max retries)
            final isRetriable =
                validation == ValidationResult.empty ||
                validation == ValidationResult.garbled;
            if (isRetriable && attempt < TokenBudgets.maxGenerationRetries) {
              debugPrint(LlmStrings.retryingGenerationLog);
              // Reset the placeholder for the next attempt
              setState(() {
                _messages[assistantIndex] = _messages[assistantIndex].copyWith(
                  content: '',
                  isStreaming: true,
                );
              });
              _startGeneration(
                query: query,
                context: context,
                promptOverride: promptOverride,
                history: history,
                retrievedDocs: retrievedDocs,
                activeSession: activeSession,
                assistantIndex: assistantIndex,
                attempt: attempt + 1,
              );
              return;
            }

            if (validation != ValidationResult.passed) {
              finalContent = OutputValidator.applyFallback(
                validation,
                finalContent,
              );
            }

            // Append citation footer if we have retrieved docs
            if (finalContent.isNotEmpty &&
                retrievedDocs.isNotEmpty &&
                validation == ValidationResult.passed) {
              finalContent = CitationExtractor.appendSourceFooter(
                finalContent,
                retrievedDocs,
              );
            }
            setState(() {
              _messages[assistantIndex] = _messages[assistantIndex].copyWith(
                isStreaming: false,
                content: finalContent.isEmpty
                    ? ValidationStrings.genericFallback
                    : finalContent,
              );
            });
            persistAssistantOnce();
            _scrollToBottom();
          },
          onError: (e) {
            if (!mounted) return;

            // Retry once on error before showing error message
            if (attempt < TokenBudgets.maxGenerationRetries) {
              debugPrint(LlmStrings.retryingGenerationLog);
              setState(() {
                _messages[assistantIndex] = _messages[assistantIndex].copyWith(
                  content: '',
                  isStreaming: true,
                );
              });
              _startGeneration(
                query: query,
                context: context,
                promptOverride: promptOverride,
                history: history,
                retrievedDocs: retrievedDocs,
                activeSession: activeSession,
                assistantIndex: assistantIndex,
                attempt: attempt + 1,
              );
              return;
            }

            setState(() {
              _messages[assistantIndex] = ChatMessage.error(
                '${LlmStrings.errorDuringGeneration}$e',
              );
            });
            persistAssistantOnce();
          },
        );
  }

  Future<void> _stopGeneration() async {
    _generationSubscription?.cancel();
    _generationSubscription = null;
    await llmService.stopGeneration();

    // Finalize the last message
    if (mounted && _messages.isNotEmpty && _messages.last.isStreaming) {
      setState(() {
        final last = _messages.last;
        _messages[_messages.length - 1] = last.copyWith(
          isStreaming: false,
          content: last.content.isEmpty
              ? LlmStrings.generationStopped
              : '${last.content}\n\n${LlmStrings.generationStopped}',
        );
      });
      final session = _currentSession;
      if (session != null) {
        _persistMessage(session, _messages.last);
      }
    }
  }

  void _startNewChat() {
    _generationSubscription?.cancel();
    _generationSubscription = null;
    llmService.stopGeneration();
    setState(() {
      _currentSession = null;
      _messages.clear();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Model Actions ─────────────────────────────────────────────────

  Future<void> _downloadModel() async {
    await llmService.downloadModel();
  }

  void _cancelDownload() {
    llmService.cancelDownload();
  }

  Future<void> _loadModel() async {
    await llmService.loadModel();
  }

  Future<void> _unloadModel() async {
    await llmService.unloadModel();
  }

  Future<void> _retryFromError() async {
    if (_modelInfo.canDownload) {
      await _downloadModel();
    } else if (_modelInfo.canLoad) {
      await _loadModel();
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentSession?.title ?? 'AI Chat'),
        actions: [
          IconButton(
            onPressed: llmService.isGenerating ? null : _openSessionSheet,
            tooltip: 'Conversations',
            icon: const Icon(Icons.history),
          ),
          if (_modelInfo.status == ModelStatus.loaded)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'new') {
                  _startNewChat();
                  return;
                }
                if (value == 'unload') {
                  _unloadModel();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'new',
                  child: Row(
                    children: [
                      Icon(Icons.add_comment_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('New Chat'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'unload',
                  child: Row(
                    children: [
                      Icon(Icons.memory, size: 20),
                      SizedBox(width: 8),
                      Text('Unload Model'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_modelInfo.status) {
      case ModelStatus.notDownloaded:
        return _NotDownloadedView(
          modelInfo: _modelInfo,
          onDownload: _downloadModel,
        );
      case ModelStatus.downloading:
        return _DownloadingView(
          modelInfo: _modelInfo,
          onCancel: _cancelDownload,
        );
      case ModelStatus.ready:
        return _ReadyView(onLoad: _loadModel);
      case ModelStatus.loading:
        return const _LoadingView();
      case ModelStatus.loaded:
        return _ChatView(
          messages: _messages,
          textController: _textController,
          scrollController: _scrollController,
          isGenerating: llmService.isGenerating,
          isSemanticSearchActive: _contextBuilder.isSemanticSearchActive,
          onSend: _sendMessage,
          onStop: _stopGeneration,
          onSuggestionTap: (text) {
            _textController.text = text;
            _sendMessage(text);
          },
        );
      case ModelStatus.error:
        return _ErrorView(modelInfo: _modelInfo, onRetry: _retryFromError);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATE 1: Model Not Downloaded
// ═══════════════════════════════════════════════════════════════════════

class _NotDownloadedView extends StatelessWidget {
  final ModelInfo modelInfo;
  final VoidCallback onDownload;

  const _NotDownloadedView({required this.modelInfo, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoshikaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.download_for_offline_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.xl),
            Text(
              'AI Assistant',
              style: KoshikaTypography.sectionHeader.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            Text(
              'Download the ${modelInfo.name} model to chat about your health data privately on this device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoshikaSpacing.base),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KoshikaSpacing.base,
                vertical: KoshikaSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: KoshikaRadius.lg,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage,
                    size: 16,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: KoshikaSpacing.sm),
                  Text(
                    'Download size: ~${modelInfo.formattedSize}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: KoshikaSpacing.base),
                  const Icon(
                    Icons.wifi,
                    size: 16,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: KoshikaSpacing.xs),
                  Text(
                    'Wi-Fi recommended',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KoshikaSpacing.xl),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download),
              label: const Text('Download AI Model'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATE 2: Downloading
// ═══════════════════════════════════════════════════════════════════════

class _DownloadingView extends StatelessWidget {
  final ModelInfo modelInfo;
  final VoidCallback onCancel;

  const _DownloadingView({required this.modelInfo, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = modelInfo.downloadProgress;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoshikaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.downloading,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.xl),
            Text(
              'Downloading ${modelInfo.name}',
              style: KoshikaTypography.sectionHeader.copyWith(
                fontSize: 20,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.xl),
            SizedBox(
              width: 280,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: KoshikaRadius.md,
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress / 100.0 : null,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: KoshikaSpacing.sm),
                  Text(
                    progress > 0
                        ? '$progress% downloaded'
                        : 'Starting download...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KoshikaSpacing.base),
            Text(
              'Please keep the app open',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: KoshikaSpacing.xl),
            OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATE 3: Ready (Downloaded, Not Loaded)
// ═══════════════════════════════════════════════════════════════════════

class _ReadyView extends StatelessWidget {
  final VoidCallback onLoad;

  const _ReadyView({required this.onLoad});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoshikaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.xl),
            Text(
              'AI Model Ready',
              style: KoshikaTypography.sectionHeader.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            Text(
              'The model is downloaded. Load it into memory to start chatting about your health data.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoshikaSpacing.xl),
            FilledButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Load Model'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATE 4: Loading
// ═══════════════════════════════════════════════════════════════════════

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoshikaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.xl),
            Text(
              'Loading AI Model...',
              style: KoshikaTypography.sectionHeader.copyWith(
                fontSize: 20,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            Text(
              'This may take a few seconds depending on your device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATE 5: Loaded — Full Chat UI
// ═══════════════════════════════════════════════════════════════════════

class _ChatView extends StatelessWidget {
  final List<ChatMessage> messages;
  final TextEditingController textController;
  final ScrollController scrollController;
  final bool isGenerating;
  final bool isSemanticSearchActive;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<String>? onSuggestionTap;

  const _ChatView({
    required this.messages,
    required this.textController,
    required this.scrollController,
    required this.isGenerating,
    this.isSemanticSearchActive = false,
    required this.onSend,
    required this.onStop,
    this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Search mode indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: KoshikaSpacing.base,
            vertical: 6,
          ),
          color: isSemanticSearchActive
              ? AppColors.primaryContainer.withValues(alpha: 0.12)
              : AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSemanticSearchActive ? Icons.auto_awesome : Icons.text_fields,
                size: 14,
                color: isSemanticSearchActive
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(width: KoshikaSpacing.xs),
              Text(
                isSemanticSearchActive
                    ? 'Semantic search active'
                    : 'Keyword search (basic)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSemanticSearchActive
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),

        // Message list
        Expanded(
          child: messages.isEmpty
              ? _EmptyChatView(onSuggestionTap: onSuggestionTap)
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoshikaSpacing.base,
                    vertical: KoshikaSpacing.sm,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return ChatMessageBubble(message: messages[index]);
                  },
                ),
        ),

        // Glassmorphic input bar
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.85),
              ),
              padding: const EdgeInsets.fromLTRB(
                KoshikaSpacing.base,
                KoshikaSpacing.sm,
                KoshikaSpacing.sm,
                KoshikaSpacing.xs,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Text input
                        Expanded(
                          child: TextField(
                            controller: textController,
                            maxLines: 5,
                            minLines: 1,
                            enabled: !isGenerating,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Ask about your health data...',
                              border: OutlineInputBorder(
                                borderRadius: KoshikaRadius.xxl,
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: AppColors.surfaceContainerLow,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: KoshikaSpacing.lg,
                                vertical: KoshikaSpacing.md,
                              ),
                            ),
                            onSubmitted: (_) => onSend(),
                          ),
                        ),
                        const SizedBox(width: KoshikaSpacing.sm),

                        // Send / Stop button
                        if (isGenerating)
                          IconButton.filledTonal(
                            onPressed: onStop,
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primaryContainer
                                  .withValues(alpha: 0.2),
                              foregroundColor: AppColors.primary,
                            ),
                            icon: const Icon(Icons.stop_rounded),
                            tooltip: 'Stop generation',
                          )
                        else
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: textController,
                            builder: (context, value, _) {
                              final hasText = value.text.trim().isNotEmpty;
                              return IconButton.filled(
                                onPressed: hasText ? onSend : null,
                                style: IconButton.styleFrom(
                                  backgroundColor: hasText
                                      ? AppColors.primary
                                      : AppColors.surfaceContainerHigh,
                                  foregroundColor: hasText
                                      ? Colors.white
                                      : AppColors.onSurfaceVariant,
                                ),
                                icon: const Icon(Icons.send_rounded),
                                tooltip: 'Send message',
                              );
                            },
                          ),
                      ],
                    ),
                    // Privacy label
                    Padding(
                      padding: const EdgeInsets.only(
                        top: KoshikaSpacing.xs,
                        bottom: KoshikaSpacing.xs,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 11,
                            color: AppColors.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'All processing happens on your device',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.onSurfaceVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Empty Chat State
// ═══════════════════════════════════════════════════════════════════════

class _EmptyChatView extends StatelessWidget {
  final ValueChanged<String>? onSuggestionTap;

  const _EmptyChatView({this.onSuggestionTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoshikaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.base),
            Text(
              'Ask about your health data',
              style: KoshikaTypography.sectionHeader.copyWith(
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            Text(
              'Your lab data is automatically included as context. '
              'Try asking:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoshikaSpacing.base),
            _SuggestionChip(
              label: 'How is my thyroid?',
              onTap: onSuggestionTap,
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            _SuggestionChip(
              label: 'What does my cholesterol mean?',
              onTap: onSuggestionTap,
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            _SuggestionChip(
              label: 'Which values are out of range?',
              onTap: onSuggestionTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final ValueChanged<String>? onTap;

  const _SuggestionChip({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => onTap?.call(label),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KoshikaSpacing.base,
          vertical: KoshikaSpacing.md,
        ),
        decoration: BoxDecoration(
          borderRadius: KoshikaRadius.xl,
          color: AppColors.surfaceContainerLow,
        ),
        child: Text(
          '"$label"',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.primary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATE 6: Error
// ═══════════════════════════════════════════════════════════════════════

class _ErrorView extends StatelessWidget {
  final ModelInfo modelInfo;
  final VoidCallback onRetry;

  const _ErrorView({required this.modelInfo, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoshikaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.errorContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.base),
            Text(
              'Something went wrong',
              style: KoshikaTypography.sectionHeader.copyWith(
                fontSize: 20,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: KoshikaSpacing.md),
            if (modelInfo.errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(KoshikaSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.4),
                  borderRadius: KoshikaRadius.lg,
                ),
                child: Text(
                  modelInfo.errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: KoshikaSpacing.xl),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
