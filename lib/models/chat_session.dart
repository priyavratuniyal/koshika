import 'package:objectbox/objectbox.dart';

/// A persisted chat conversation.
@Entity()
class ChatSession {
  @Id()
  int id;

  /// Auto-generated from the first user message.
  String title;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime lastMessageAt;

  ChatSession({
    this.id = 0,
    required this.title,
    DateTime? createdAt,
    DateTime? lastMessageAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       lastMessageAt = lastMessageAt ?? DateTime.now();
}

/// A single persisted message belonging to a [ChatSession].
@Entity()
class PersistedChatMessage {
  @Id()
  int id;

  final session = ToOne<ChatSession>();

  String content;

  /// 0=user, 1=assistant, 2=system (mapped from ChatRole.index).
  int roleIndex;

  @Property(type: PropertyType.date)
  DateTime timestamp;

  bool isError;

  PersistedChatMessage({
    this.id = 0,
    required this.content,
    required this.roleIndex,
    DateTime? timestamp,
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();
}
