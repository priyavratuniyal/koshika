import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/chat_context_builder.dart';
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

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _contextBuilder = ChatContextBuilder();

  StreamSubscription<ModelInfo>? _statusSubscription;
  StreamSubscription<String>? _generationSubscription;
  ModelInfo _modelInfo = gemmaService.currentModelInfo;

  @override
  void initState() {
    super.initState();
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

  // ─── Chat Logic ────────────────────────────────────────────────────

  void _sendMessage([String? overrideText]) {
    final text = (overrideText ?? _textController.text).trim();
    if (text.isEmpty || !mounted) return;
    if (gemmaService.isGenerating) return;

    _textController.clear();

    // Add user message
    final userMsg = ChatMessage.user(text);
    setState(() {
      _messages.add(userMsg);
    });
    _scrollToBottom();

    // Build context from lab data
    final context = _contextBuilder.buildQueryContext(text);

    // Add placeholder assistant message (streaming)
    final assistantMsg = ChatMessage.assistantStreaming();
    setState(() {
      _messages.add(assistantMsg);
    });
    _scrollToBottom();

    // Start streaming generation
    final assistantIndex = _messages.length - 1;
    final tokenBuffer = StringBuffer();

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
              setState(() {
                _messages[assistantIndex] = _messages[assistantIndex].copyWith(
                  isStreaming: false,
                  // If we got no tokens, show a fallback message
                  content: tokenBuffer.isEmpty
                      ? 'I wasn\'t able to generate a response. Please try again.'
                      : null,
                );
              });
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
    }
  }

  void _clearChat() {
    setState(() {
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
    await gemmaService.downloadModel();
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

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat'),
        actions: [
          if (_modelInfo.status == ModelStatus.loaded)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'clear':
                    _clearChat();
                  case 'unload':
                    _unloadModel();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all, size: 20),
                      SizedBox(width: 8),
                      Text('Clear Chat'),
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
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<String>? onSuggestionTap;

  const _ChatView({
    required this.messages,
    required this.textController,
    required this.scrollController,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
    this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
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
