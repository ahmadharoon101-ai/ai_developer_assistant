import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/chat_repository.dart';
import '../domain/chat_models.dart';

const kNewChatKey = '__new__';
const Object _keep = Object();

final chatRepositoryProvider = Provider<ChatRepository>((ref) =>
    ApiChatRepository(ref.read(dioProvider), ref.read(tokenStorageProvider)));

class ChatState {
  const ChatState({
    required this.conversations,
    required this.activeId,
    required this.messages,
    this.projectId,
    this.isStreaming = false,
    this.isLoadingList = false,
    this.isLoadingMessages = false,
    this.listError,
    this.pendingImages = const [],
  });

  final List<Conversation> conversations;

  /// null = a brand-new conversation that the server has not created yet.
  final String? activeId;
  final Map<String, List<ChatMessage>> messages;

  /// Project attached as context for the next messages.
  final String? projectId;
  final bool isStreaming;
  final bool isLoadingList;
  final bool isLoadingMessages;
  final String? listError;

  /// Images picked in the composer, waiting to be sent with the next message.
  final List<ImageAttachment> pendingImages;

  List<ChatMessage> get activeMessages => messages[activeId ?? kNewChatKey] ?? const [];

  ChatState copyWith({
    List<Conversation>? conversations,
    Object? activeId = _keep,
    Map<String, List<ChatMessage>>? messages,
    Object? projectId = _keep,
    bool? isStreaming,
    bool? isLoadingList,
    bool? isLoadingMessages,
    Object? listError = _keep,
    List<ImageAttachment>? pendingImages,
  }) =>
      ChatState(
        conversations: conversations ?? this.conversations,
        activeId: identical(activeId, _keep) ? this.activeId : activeId as String?,
        messages: messages ?? this.messages,
        projectId: identical(projectId, _keep) ? this.projectId : projectId as String?,
        isStreaming: isStreaming ?? this.isStreaming,
        isLoadingList: isLoadingList ?? this.isLoadingList,
        isLoadingMessages: isLoadingMessages ?? this.isLoadingMessages,
        listError: identical(listError, _keep) ? this.listError : listError as String?,
        pendingImages: pendingImages ?? this.pendingImages,
      );
}

class ChatController extends Notifier<ChatState> {
  int _seq = 0;
  int _gen = 0;
  bool _cancelled = false;

  String _id() => 'm${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  ChatState build() {
    _gen++;
    // Rebuild (and drop all state) when a different user signs in.
    final uid = ref.watch(authControllerProvider.select((a) => a.valueOrNull?.id));
    if (uid != null) Future.microtask(loadConversations);
    return ChatState(
      conversations: const [],
      activeId: null,
      messages: {kNewChatKey: <ChatMessage>[]},
      isLoadingList: uid != null,
    );
  }

  // ---- state helpers -------------------------------------------------------

  void _setMessages(String key, List<ChatMessage> Function(List<ChatMessage>) f) {
    final next = Map<String, List<ChatMessage>>.from(state.messages);
    next[key] = f(List<ChatMessage>.from(next[key] ?? const []));
    state = state.copyWith(messages: next);
  }

  void _replace(String key, String id, ChatMessage Function(ChatMessage) f) =>
      _setMessages(key, (l) => [for (final m in l) m.id == id ? f(m) : m]);

  void _finishTools(String key) => _setMessages(
      key,
      (l) => [
            for (final m in l)
              (m.role == MessageRole.tool && m.streaming)
                  ? m.copyWith(streaming: false)
                  : m
          ]);

  // ---- public actions ------------------------------------------------------

  Future<void> loadConversations() async {
    final gen = _gen;
    state = state.copyWith(isLoadingList: true, listError: null);
    try {
      final list = await _repo.listConversations();
      if (gen != _gen) return;
      state = state.copyWith(conversations: list, isLoadingList: false);
    } catch (e) {
      if (gen != _gen) return;
      state = state.copyWith(isLoadingList: false, listError: toApiException(e).message);
    }
  }

  void newConversation() {
    if (state.activeId == null && state.activeMessages.isEmpty) return;
    final next = Map<String, List<ChatMessage>>.from(state.messages);
    if (!state.isStreaming) next[kNewChatKey] = <ChatMessage>[];
    state = state.copyWith(activeId: null, messages: next);
  }

  Future<void> select(String id) async {
    state = state.copyWith(activeId: id);
    if (state.messages.containsKey(id)) return;
    state = state.copyWith(isLoadingMessages: true, listError: null);
    try {
      final msgs = await _repo.loadMessages(id);
      state = state.copyWith(
          messages: {...state.messages, id: msgs}, isLoadingMessages: false);
    } catch (e) {
      state = state.copyWith(isLoadingMessages: false, listError: toApiException(e).message);
    }
  }

  void setProject(String? projectId) => state = state.copyWith(projectId: projectId);

  static const _maxImages = 4;

  /// Returns an error message if the image couldn't be added, else null.
  String? addPendingImage(ImageAttachment image) {
    if (state.pendingImages.length >= _maxImages) {
      return 'You can attach up to $_maxImages images per message.';
    }
    state = state.copyWith(pendingImages: [...state.pendingImages, image]);
    return null;
  }

  void removePendingImage(int index) {
    final next = List<ImageAttachment>.from(state.pendingImages)..removeAt(index);
    state = state.copyWith(pendingImages: next);
  }

  void clearPendingImages() => state = state.copyWith(pendingImages: const []);

  Future<void> deleteConversation(String id) async {
    try {
      await _repo.deleteConversation(id);
    } catch (e) {
      state = state.copyWith(listError: toApiException(e).message);
      return;
    }
    final msgs = Map<String, List<ChatMessage>>.from(state.messages)..remove(id);
    state = state.copyWith(
      conversations: [for (final c in state.conversations) if (c.id != id) c],
      messages: msgs,
      activeId: state.activeId == id ? null : state.activeId,
    );
  }

  Future<void> send(String text) async {
    final prompt = text.trim();
    final images = state.pendingImages;
    if ((prompt.isEmpty && images.isEmpty) || state.isStreaming) return;
    final convId = state.activeId;
    _setMessages(convId ?? kNewChatKey, (l) => [
          ...l,
          ChatMessage(id: _id(), role: MessageRole.user, content: prompt, images: images),
        ]);
    clearPendingImages();
    await _stream(convId, prompt, images: images);
  }

  /// Starts a fresh conversation with [text] (used by the dashboard and other tools).
  Future<void> startWith(String text, {String? projectId}) async {
    if (state.isStreaming) return;
    newConversation();
    if (projectId != null) setProject(projectId);
    await send(text);
  }

  Future<void> regenerate() async {
    if (state.isStreaming || state.activeId == null) return;
    final convId = state.activeId!;
    final list = state.activeMessages;
    final lastUser = list.lastIndexWhere((m) => m.role == MessageRole.user);
    if (lastUser < 0) return;
    _setMessages(convId, (l) => l.sublist(0, lastUser + 1));
    await _stream(convId, '', regenerate: true);
  }

  void stop() => _cancelled = true;

  // ---- streaming -----------------------------------------------------------

  Future<void> _stream(String? convId, String prompt,
      {bool regenerate = false, List<ImageAttachment> images = const []}) async {
    _cancelled = false;
    state = state.copyWith(isStreaming: true);
    var key = convId ?? kNewChatKey;
    String? aiId;
    try {
      await for (final e in _repo.streamReply(convId, prompt,
          projectId: state.projectId, regenerate: regenerate, images: images)) {
        if (_cancelled) break;
        switch (e) {
          case ConversationCreated(:final id, :final title):
            final msgs = Map<String, List<ChatMessage>>.from(state.messages);
            msgs[id] = msgs[kNewChatKey] ?? <ChatMessage>[];
            msgs[kNewChatKey] = <ChatMessage>[];
            state = state.copyWith(
              conversations: [
                Conversation(id: id, title: title, updated: 'Just now'),
                ...state.conversations,
              ],
              activeId: state.activeId == null ? id : state.activeId,
              messages: msgs,
            );
            key = id;
          case ToolStatus(:final text):
            _finishTools(key);
            _setMessages(key, (l) => [
                  ...l,
                  ChatMessage(id: _id(), role: MessageRole.tool, content: text, streaming: true),
                ]);
          case Token(:final text):
            _finishTools(key);
            if (aiId == null) {
              final id = _id();
              aiId = id;
              _setMessages(key, (l) => [
                    ...l,
                    ChatMessage(id: id, role: MessageRole.ai, content: text, streaming: true),
                  ]);
            } else {
              _replace(key, aiId, (m) => m.copyWith(content: m.content + text));
            }
          case StreamDone():
            break;
        }
      }
    } catch (err) {
      _setMessages(key, (l) => [
            ...l,
            ChatMessage(
              id: _id(),
              role: MessageRole.tool,
              content: toApiException(err).message,
              isError: true,
            ),
          ]);
    } finally {
      _finishTools(key);
      if (aiId != null) _replace(key, aiId, (m) => m.copyWith(streaming: false));
      state = state.copyWith(isStreaming: false);
    }
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);
