import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';

/// Renders a single chat message with role-based styling.
///
/// - User messages: right-aligned, primary-color bubble, 24px radius
/// - Assistant messages: left-aligned, surface bubble with 4px left accent strip
/// - Error messages: left-aligned, error-container bubble
/// - Streaming messages: show animated "..." indicator at the end
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final isError = message.isError;

    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;

    Color bubbleColor;
    Color textColor;
    if (isError) {
      bubbleColor = AppColors.errorContainer;
      textColor = AppColors.onErrorContainer;
    } else if (isUser) {
      bubbleColor = AppColors.primary;
      textColor = Colors.white;
    } else {
      bubbleColor = AppColors.surfaceContainerLowest;
      textColor = AppColors.onSurface;
    }

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: KoshikaSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: KoshikaSpacing.base,
          vertical: KoshikaSpacing.md,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: KoshikaRadius.xxl,
          border: (!isUser && !isError)
              ? const Border(
                  left: BorderSide(color: AppColors.primary, width: 4),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // AI label for assistant messages
            if (!isUser && !isError)
              Padding(
                padding: const EdgeInsets.only(bottom: KoshikaSpacing.xs),
                child: Text(
                  'KOSHIKA INTELLIGENCE',
                  style: KoshikaTypography.metricLabel.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 1.0,
                  ),
                ),
              ),

            // Error icon row
            if (isError)
              Padding(
                padding: const EdgeInsets.only(bottom: KoshikaSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: KoshikaSpacing.xs),
                    Text(
                      'Error',
                      style: KoshikaTypography.statusText.copyWith(
                        color: AppColors.error,
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
                padding: const EdgeInsets.only(top: KoshikaSpacing.xs),
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
    if (t < 0.5) return t * 2;
    return (1 - t) * 2;
  }
}
