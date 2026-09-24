import 'dart:typed_data';

enum MessageRole { user, ai, tool }

/// A picked image, held in memory only. Sent live to the model but not
/// persisted server-side, so it won't reappear if the conversation reloads.
class ImageAttachment {
  const ImageAttachment({required this.bytes, required this.mime, required this.name});
  final Uint8List bytes;
  final String mime;
  final String name;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.streaming = false,
    this.isError = false,
    this.images = const [],
  });

  final String id;
  final MessageRole role;
  final String content;

  /// AI: tokens still arriving. Tool: step still running.
  final bool streaming;
  final bool isError;
  final List<ImageAttachment> images;

  ChatMessage copyWith({String? content, bool? streaming}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        streaming: streaming ?? this.streaming,
        isError: isError,
        images: images,
      );
}

class Conversation {
  const Conversation({required this.id, required this.title, required this.updated});
  final String id;
  final String title;
  final String updated;

  Conversation copyWith({String? title, String? updated}) => Conversation(
      id: id, title: title ?? this.title, updated: updated ?? this.updated);
}

/// Events streamed from the backend over /ws/chat.
sealed class ChatEvent {
  const ChatEvent();
}

class ConversationCreated extends ChatEvent {
  const ConversationCreated(this.id, this.title);
  final String id;
  final String title;
}

class ToolStatus extends ChatEvent {
  const ToolStatus(this.text);
  final String text;
}

class Token extends ChatEvent {
  const Token(this.text);
  final String text;
}

class StreamDone extends ChatEvent {
  const StreamDone();
}
