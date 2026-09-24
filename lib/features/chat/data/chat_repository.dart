import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/chat_models.dart';

abstract class ChatRepository {
  Future<List<Conversation>> listConversations();
  Future<List<ChatMessage>> loadMessages(String conversationId);
  Future<void> deleteConversation(String conversationId);
  Stream<ChatEvent> streamReply(String? conversationId, String prompt,
      {String? projectId, bool regenerate = false, List<ImageAttachment> images = const []});
}

/// base64-encodes attachments for the WS "images" field: [{"mime","data"}].
List<Map<String, String>> _encodeImages(List<ImageAttachment> images) => [
      for (final img in images) {'mime': img.mime, 'data': base64Encode(img.bytes)}
    ];

/// REST for history, WebSocket for streaming.
///
/// Client -> server:  {"type":"auth","token":"<jwt>"}  (first frame, never in the URL)
///                    {"type":"message","conversation_id":null|"..","content":"..",
///                     "project_id":null|"..","regenerate":false}
/// Server -> client:  conversation | status | token | done | error
class ApiChatRepository implements ChatRepository {
  ApiChatRepository(this._dio, this._storage);
  final Dio _dio;
  final TokenStorage _storage;

  @override
  Future<List<Conversation>> listConversations() async {
    try {
      final res = await _dio.get<dynamic>(ApiConstants.conversations);
      return [
        for (final c in res.data as List)
          Conversation(
            id: c['id'] as String,
            title: c['title'] as String,
            updated: relativeTime(c['updated_at'] as String?),
          )
      ];
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<List<ChatMessage>> loadMessages(String conversationId) async {
    try {
      final res = await _dio
          .get<dynamic>('${ApiConstants.conversations}/$conversationId/messages');
      return [
        for (final m in res.data as List)
          ChatMessage(
            id: 'srv_${m['id']}',
            role: m['role'] == 'user' ? MessageRole.user : MessageRole.ai,
            content: m['content'] as String,
          )
      ];
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    try {
      await _dio.delete<dynamic>('${ApiConstants.conversations}/$conversationId');
    } catch (e) {
      throw toApiException(e);
    }
  }

  @override
  Stream<ChatEvent> streamReply(String? conversationId, String prompt,
      {String? projectId, bool regenerate = false, List<ImageAttachment> images = const []}) async* {
    final token = await _storage.readAccessToken();
    final channel = WebSocketChannel.connect(Uri.parse(ApiConstants.wsUrl));
    var finished = false;
    try {
      await channel.ready;
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      channel.sink.add(jsonEncode({
        'type': 'message',
        'conversation_id': conversationId,
        'content': prompt,
        'project_id': projectId,
        'regenerate': regenerate,
        'images': _encodeImages(images),
      }));
      await for (final raw in channel.stream) {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        switch (m['type']) {
          case 'conversation':
            yield ConversationCreated(m['id'] as String, m['title'] as String);
          case 'status':
            yield ToolStatus(m['content'] as String);
          case 'token':
            yield Token(m['content'] as String);
          case 'error':
            throw ApiException(m['content'] as String? ?? 'The assistant hit an error.');
          case 'done':
            finished = true;
            yield const StreamDone();
            return;
        }
      }
      if (!finished) {
        throw ApiException(channel.closeCode == 4401
            ? 'Your session expired. Sign out and sign in again.'
            : 'The connection closed before the reply finished.');
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
          'Could not connect to the assistant. Is the backend running and reachable?');
    } finally {
      await channel.sink.close();
    }
  }
}
