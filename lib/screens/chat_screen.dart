import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/chat_context_builder.dart';
import '../services/citation_extractor.dart';
import '../services/embedding_service.dart';
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
  ChatSession? _currentSession;
  bool _hasShownPersistenceWarning = false;
  bool _hasLoggedUnknownRoleIndex = false;

  StreamSubscription<ModelInfo>? _statusSubscription;
  StreamSubscription<String>? _generationSubscription;
  ModelInfo _modelInfo = gemmaService.currentModelInfo;

  @override
  void initState() {
    super.initState();
    _contextBuilder = ChatContextBuilder(vectorStore: vectorStoreService);
    _loadMostRecentSession();
    _statusSubscription = gemmaService.modelStatusStream.listen((info) {
      if (mounted) {
        setState(() => _modelInfo = info);
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _generationSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMostRecentSession() {
    try {
      final sessions = objectbox.getAllSessions();
      if (sessions.isEmpty) return;

      final session = sessions.first;
      final persisted = objectbox.getMessagesForSession(session.id);
      _currentSession = session;
      _messages.addAll(
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
    } catch (e, st) {
      _logStorageError('load most recent session', e, st);
    }
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
      const SnackBar(
        content: Text('Could not save chat history for one or more messages.'),
      ),
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
                const Divider(height: 1),
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
    await gemmaService.stopGeneration();

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

  Future<void> _sendMessage([String? overrideText]) async {
    final text = (overrideText ?? _textController.text).trim();
    if (text.isEmpty || !mounted) return;
    if (gemmaService.isGenerating) return;

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

    // Build context from lab data (async — may use semantic search)
    final context = await _contextBuilder.buildQueryContext(text);
    final retrievedDocs = List<RetrievalResult>.from(
      _contextBuilder.lastRetrievedDocs,
    );

    if (!mounted) return;

    // Add placeholder assistant message (streaming)
    final assistantMsg = ChatMessage.assistantStreaming();
    setState(() {
      _messages.add(assistantMsg);
    });
    _scrollToBottom();

    // Start streaming generation
    final assistantIndex = _messages.length - 1;
    final tokenBuffer = StringBuffer();
    var assistantPersistAttempted = false;

    void persistAssistantOnce() {
      final session = activeSession;
      if (session == null || assistantPersistAttempted) return;
      assistantPersistAttempted = true;
      _persistMessage(session, _messages[assistantIndex]);
    }

    _generationSubscription?.cancel();
    _generationSubscription = gemmaService
        .generateResponse(text, context: context)
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
            if (mounted) {
              var finalContent = tokenBuffer.toString();
              // Append citation footer if we have retrieved docs
              if (finalContent.isNotEmpty && retrievedDocs.isNotEmpty) {
                finalContent = CitationExtractor.appendSourceFooter(
                  finalContent,
                  retrievedDocs,
                );
              }
              setState(() {
                _messages[assistantIndex] = _messages[assistantIndex].copyWith(
                  isStreaming: false,
                  content: finalContent.isEmpty
                      ? 'I wasn\'t able to generate a response. Please try again.'
                      : finalContent,
                );
              });
              persistAssistantOnce();
              _scrollToBottom();
            }
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                _messages[assistantIndex] = ChatMessage.error(
                  'An error occurred during generation: $e',
                );
              });
              persistAssistantOnce();
            }
          },
        );
  }

  Future<void> _stopGeneration() async {
    _generationSubscription?.cancel();
    _generationSubscription = null;
    await gemmaService.stopGeneration();

    // Finalize the last message
    if (mounted && _messages.isNotEmpty && _messages.last.isStreaming) {
      setState(() {
        final last = _messages.last;
        _messages[_messages.length - 1] = last.copyWith(
          isStreaming: false,
          content: last.content.isEmpty
              ? '[Generation stopped]'
              : '${last.content}\n\n[Generation stopped]',
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
    gemmaService.stopGeneration();
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
    final token = await _getOrPromptHfToken();
    if (token == null || token.isEmpty) return;
    await gemmaService.downloadModel(hfToken: token);
  }

  void _cancelDownload() {
    gemmaService.cancelDownload();
  }

  Future<void> _loadModel() async {
    await gemmaService.loadModel();
  }

  Future<void> _unloadModel() async {
    await gemmaService.unloadModel();
  }

  Future<void> _retryFromError() async {
    // Determine what to retry based on current state history
    if (_modelInfo.canDownload) {
      await _downloadModel();
    } else if (_modelInfo.canLoad) {
      await _loadModel();
    }
  }

  Future<String?> _getOrPromptHfToken() async {
    var token = await EmbeddingService.getHfToken();
    if (token != null && token.isNotEmpty) return token;
    if (!mounted) return null;

    final controller = TextEditingController();
    token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hugging Face Token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The chat model is gated on Hugging Face and needs a token with '
              'read access.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Grant access to litert-community/Gemma3-1B-IT, create a Read '
              'token, then paste it here.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Access Token',
                hintText: 'hf_...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
              autocorrect: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.of(context).pop(value);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (token == null || token.isEmpty) return null;
    await EmbeddingService.saveHfToken(token);
    return token;
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentSession?.title ?? 'AI Chat'),
        actions: [
          IconButton(
            onPressed: gemmaService.isGenerating ? null : _openSessionSheet,
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
          isGenerating: gemmaService.isGenerating,
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_for_offline_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'AI Assistant',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Download the ${modelInfo.name} model to chat about your health data privately on this device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.storage,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Download size: ~${modelInfo.formattedSize}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'Wi-Fi recommended',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.downloading, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'Downloading ${modelInfo.name}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 280,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress / 100.0 : null,
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress > 0
                        ? '$progress% downloaded'
                        : 'Starting download...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please keep the app open',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'AI Model Ready',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The model is downloaded. Load it into memory to start chatting about your health data.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.play_arrow),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading AI Model...',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a few seconds depending on your device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSemanticSearchActive ? Icons.auto_awesome : Icons.text_fields,
                size: 14,
                color: isSemanticSearchActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                isSemanticSearchActive
                    ? 'Semantic search active'
                    : 'Keyword search (basic)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSemanticSearchActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return ChatMessageBubble(message: messages[index]);
                  },
                ),
        ),

        // Input bar
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: SafeArea(
            top: false,
            child: Row(
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
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),

                // Send / Stop button
                if (isGenerating)
                  IconButton.filledTonal(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop),
                    tooltip: 'Stop generation',
                  )
                else
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: textController,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      return IconButton.filled(
                        onPressed: hasText ? onSend : null,
                        icon: const Icon(Icons.send),
                        tooltip: 'Send message',
                      );
                    },
                  ),
              ],
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Ask about your health data',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your lab data is automatically included as context. '
              'Try asking:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _SuggestionChip(
              label: 'How is my thyroid?',
              onTap: onSuggestionTap,
            ),
            const SizedBox(height: 8),
            _SuggestionChip(
              label: 'What does my cholesterol mean?',
              onTap: onSuggestionTap,
            ),
            const SizedBox(height: 8),
            _SuggestionChip(
              label: 'Which values are out of range?',
              onTap: onSuggestionTap,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  'All processing happens on your device',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          '"$label"',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (modelInfo.errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  modelInfo.errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
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
