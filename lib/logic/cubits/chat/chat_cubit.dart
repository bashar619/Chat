// lib/logic/chat/chat_cubit.dart
import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';

import 'package:youtube_messenger_app/data/repositories/chat_repository.dart';
import 'package:youtube_messenger_app/logic/cubits/chat/chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  final ChatRepository _chatRepository;
  final String currentUserId;
  bool _isInChat = false;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _onlineStatusSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _blockStatusSubscription;
  StreamSubscription? _amIBlockStatusSubscription;
  Timer? typingTimer;

  ChatCubit({
    required ChatRepository chatRepository,
    required this.currentUserId,
  })  : _chatRepository = chatRepository,
        super(const ChatState());

  void enterChat(String receiverId) async {
    _isInChat = true;
    emit(state.copyWith(status: ChatStatus.loading));
    try {
      final chatRoom =
          await _chatRepository.getOrCreateChatRoom(currentUserId, receiverId);
      emit(state.copyWith(
        chatRoomId: chatRoom.id,
        receiverId: receiverId,
        status: ChatStatus.loaded,
      ));

      //subscribe to all updates
      _subscribeToMessages(chatRoom.id);
      _subscribeToOnlineStatus(receiverId);
      _subscribeToTypingStatus(chatRoom.id);
      _subscribeToBlockStatus(receiverId);

      await _chatRepository.updateOnlineStatus(currentUserId, true);
    } catch (e) {
      emit(state.copyWith(
          status: ChatStatus.error, error: "Failed to create chat room $e"));
    }
  }

   Future<void> sendMessage({
   required String content,
   required String receiverId,
   MessageType type = MessageType.text,
 }) async {
     if (state.chatRoomId == null) return;
     try {
       await _chatRepository.sendMessage(
         chatRoomId: state.chatRoomId!,
         senderId: currentUserId,
         receiverId: receiverId,
         content: content,
        type: type,
       );
    } catch (e) {
      log(e.toString());
      emit(state.copyWith(error: "Failed to send message"));
    }
  }

  Future<void> loadMoreMessages() async {
    if (state.status != ChatStatus.loaded ||
        state.messages.isEmpty ||
        !state.hasMoreMessages ||
        state.isLoadingMore) return;

    try {
      emit(state.copyWith(isLoadingMore: true));

      final lastMessage = state.messages.last;
      final lastDoc = await _chatRepository
          .getChatRoomMessages(state.chatRoomId!)
          .doc(lastMessage.id)
          .get();

      final moreMessages = await _chatRepository
          .getMoreMessages(state.chatRoomId!, lastDocument: lastDoc);

      if (moreMessages.isEmpty) {
        emit(state.copyWith(hasMoreMessages: false, isLoadingMore: false));
        return;
      }

      emit(
        state.copyWith(
            messages: [...state.messages, ...moreMessages],
            hasMoreMessages: moreMessages.length >= 20,
            isLoadingMore: false),
      );
    } catch (e) {
      emit(state.copyWith(
          error: "Failed to laod more messages", isLoadingMore: false));
    }
  }

  void _subscribeToMessages(String chatRoomId) {
    _messageSubscription?.cancel();
    _messageSubscription =
        _chatRepository.getMessages(chatRoomId).listen((messages) {
      if (_isInChat) {
        _markMessagesAsRead(chatRoomId);
      }
      emit(
        state.copyWith(
          messages: messages,
          error: null,
        ),
      );
    }, onError: (error) {
      emit(
        state.copyWith(
            error: "Failed to load messages", status: ChatStatus.error),
      );
    });
  }

  void _subscribeToOnlineStatus(String userId) {
    _onlineStatusSubscription?.cancel();
    _onlineStatusSubscription =
        _chatRepository.getUserOnlineStatus(userId).listen((status) {
      final isOnline = status["isOnline"] as bool;
      final lastSeen = status["lastSeen"] as Timestamp?;

      emit(state.copyWith(
        isReceiverOnline: isOnline,
        receiverLastSeen: lastSeen,
      ));
    }, onError: (error) {
      print("error getting online status");
    });
  }

  void _subscribeToTypingStatus(String chatRoomId) {
    _typingSubscription?.cancel();
    _typingSubscription =
        _chatRepository.getTypingStatus(chatRoomId).listen((status) {
      final isTyping = status["isTyping"] as bool;
      final typingUserId = status["typingUserId"] as String?;

      emit(
        state.copyWith(
            isReceiverTyping: isTyping && typingUserId != currentUserId),
      );
    }, onError: (error) {
      print("error getting online status");
    });
  }

  void _subscribeToBlockStatus(String otherUserId) {
    _blockStatusSubscription?.cancel();
    _blockStatusSubscription = _chatRepository
        .isUserBlocked(currentUserId, otherUserId)
        .listen((isBlocked) {
      emit(
        state.copyWith(isUserBlocked: isBlocked),
      );

      _amIBlockStatusSubscription?.cancel();
      _blockStatusSubscription = _chatRepository
          .amIBlocked(currentUserId, otherUserId)
          .listen((isBlocked) {
        emit(
          state.copyWith(amIBlocked: isBlocked),
        );
      });
    }, onError: (error) {
      print("error getting online status");
    });
  }

  void startTyping() {
    if (state.chatRoomId == null) return;
    typingTimer?.cancel();
    _updateTypingStatus(true);
    typingTimer = Timer(const Duration(seconds: 3), () {
      _updateTypingStatus(false);
    });
  }

  Future<void> _updateTypingStatus(bool isTyping) async {
    if (state.chatRoomId == null) return;

    try {
      await _chatRepository.updateTypingStatus(
          state.chatRoomId!, currentUserId, isTyping);
    } catch (e) {
      print("error updating typing status $e");
    }
  }

  Future<void> blockUser(String userId) async {
    try {
      await _chatRepository.blockUser(currentUserId, userId);
    } catch (e) {
      emit(
        state.copyWith(error: 'failed to block user $e'),
      );
    }
  }

  Future<void> unBlockUser(String userId) async {
    try {
      await _chatRepository.unBlockUser(currentUserId, userId);
    } catch (e) {
      emit(
        state.copyWith(error: 'failed to unblock user $e'),
      );
    }
  }

  Future<void> _markMessagesAsRead(String chatRoomId) async {
    try {
      await _chatRepository.markMessagesAsRead(chatRoomId, currentUserId);
    } catch (e) {
      print("error marking messages as read $e");
    }
  }

  Future<void> leaveChat() async {
    _isInChat = false;
  }
 /// Unsend (delete) a message by its ID
  Future<void> deleteMessage(String messageId) async {
    final roomId = state.chatRoomId;
    if (roomId == null) return;
    try {
      await _chatRepository.deleteMessage(
        chatRoomId: roomId,
        messageId: messageId,
      );
      // Firestore stream will automatically emit the updated list
    } catch (e) {
      emit(state.copyWith(error: 'Failed to delete message: $e'));
    }
  }
   /// Edit the content of a text message
  Future<void> editMessage({
    required String messageId,
    required String newContent,
  }) async {
    final roomId = state.chatRoomId;
    if (roomId == null) return;
    try {
      await _chatRepository.editMessage(
        chatRoomId: roomId,
        messageId: messageId,
        newContent: newContent,
      );
      // The Firestore stream will push the updated message
    } catch (e) {
      emit(state.copyWith(error: 'Failed to edit message: $e'));
    }
  }

  // firestore message rection
  Future<void> addReaction({
  required String messageId,
  required String emoji,
}) async {
  final roomId = state.chatRoomId;
  if (roomId == null) return;
  try {
    await _chatRepository.addReaction(
      chatRoomId: roomId,
      messageId: messageId,
      emoji: emoji,
    );
  } catch (e) {
    emit(state.copyWith(error: 'Failed to react: $e'));
  }
}
}

