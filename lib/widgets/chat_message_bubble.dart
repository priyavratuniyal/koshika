import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';

/// Renders a single chat message with role-based styling.
///
/// - User messages: right-aligned, primary-color bubble
/// - Assistant messages: left-aligned, surface-variant bubble
/// - Error messages: left-aligned, error-container bubble
/// - Streaming messages: show animated "..." indicator at the end
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final isError = message.isError;

    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
      bottomRight: isUser ? Radius.zero : const Radius.circular(16),
    );

    Color bubbleColor;
    Color textColor;
    if (isError) {
      bubbleColor = theme.colorScheme.errorContainer;
      textColor = theme.colorScheme.onErrorContainer;
    } else if (isUser) {
      bubbleColor = theme.colorScheme.primary;
      textColor = theme.colorScheme.onPrimary;
    } else {
      bubbleColor = theme.colorScheme.surfaceContainerHighest;
      textColor = theme.colorScheme.onSurface;
    }

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: borderRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error icon row
            if (isError)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Error',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),

            // Message content — or streaming dots if content is empty
            if (message.content.isEmpty && message.isStreaming)
              _StreamingDots(color: textColor)
            else
              SelectableText(
                message.content,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.4),
              ),

            // Streaming indicator appended to text
            if (message.content.isNotEmpty && message.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _StreamingDots(color: textColor),
              ),

            // Timestamp
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                DateFormat('h:mm a').format(message.timestamp),
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated three-dot streaming indicator.
class _StreamingDots extends StatefulWidget {
  final Color color;

  const _StreamingDots({required this.color});

  @override
  State<_StreamingDots> createState() => _StreamingDotsState();
}

class _StreamingDotsState extends State<_StreamingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            // Each dot pulses with a phase offset
            final delay = index * 0.2;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity = (0.3 + 0.7 * _pulseValue(t));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  double _pulseValue(double t) {
    // Simple sine-like pulse: goes 0 → 1 → 0 over a cycle
    if (t < 0.5) return t * 2;
    return (1 - t) * 2;
  }
}
