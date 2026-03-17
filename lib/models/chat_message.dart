import 'package:uuid/uuid.dart';

/// Role of a chat message.
enum ChatRole { user, assistant, system }

/// Represents a single message in the AI chat conversation.
///
/// NOT stored in ObjectBox — chat is ephemeral (session-only).
/// Users interact with their lab data through the AI, but chat history
/// is intentionally not persisted for MVP simplicity.
class ChatMessage {
  final String id;
  final String content;
  final ChatRole role;
  final DateTime timestamp;
  final bool isStreaming;
  final bool isError;

  ChatMessage({
    String? id,
    required this.content,
    required this.role,
    DateTime? timestamp,
    this.isStreaming = false,
    this.isError = false,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  /// Create a copy with updated fields (used for streaming token append).
  ChatMessage copyWith({String? content, bool? isStreaming, bool? isError}) {
    return ChatMessage(
      id: id,
      content: content ?? this.content,
      role: role,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
    );
  }

  /// Factory for a user message.
  factory ChatMessage.user(String content) {
    return ChatMessage(content: content, role: ChatRole.user);
  }

  /// Factory for the start of an assistant response (streaming begins).
  factory ChatMessage.assistantStreaming() {
    return ChatMessage(
      content: '',
      role: ChatRole.assistant,
      isStreaming: true,
    );
  }

  /// Factory for an error message displayed in the chat.
  factory ChatMessage.error(String message) {
    return ChatMessage(
      content: message,
      role: ChatRole.assistant,
      isError: true,
    );
  }
}
