// lib/data/models/chat_message.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video , voice, document, mediaCollection, deleted}

enum MessageStatus { sent, read }

class ChatMessage {
  final String id;
  final String chatRoomId;
  final String senderId;
  final String receiverId;
  final String content;
  final MessageType type;
  final MessageStatus status;
  final Timestamp timestamp;
  final List<String> readBy;
  final String? replyToMessageId;
  final String? replyToContent;
  final MessageType? replyToType;
  final Map<String, int> reactions;
  final Map<String, String> userReactions;

  ChatMessage({
    required this.id,
    required this.chatRoomId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    required this.timestamp,
    required this.readBy,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToType,
    this.reactions = const {},
    this.userReactions = const {},
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final replyData = data['replyTo'] as Map<String, dynamic>?;
    return ChatMessage(
      id: doc.id,
      chatRoomId: data['chatRoomId'] as String,
      senderId: data['senderId'] as String,
      receiverId: data['receiverId'] as String,
      content: data['content'] as String,
      reactions: Map<String, int>.from(data['reactions'] ?? {}),
      userReactions: Map<String, String>.from(data['userReactions'] ?? {}),
      // parse replyTo if present
      replyToMessageId: replyData?['messageId'] as String?,
      replyToContent: replyData?['content'] as String?,
      replyToType: replyData != null
        ? MessageType.values.firstWhere(
            (e) => e.toString().split('.').last == replyData['type'],
            orElse: () => MessageType.text,
          )
        : null,
      type: MessageType.values.firstWhere(
    (e) => e.toString().split('.').last == data['type'],
    orElse: () => MessageType.text,
),
      status: MessageStatus.values.firstWhere(
          (e) => e.toString() == data['status'],
          orElse: () => MessageStatus.sent),
      timestamp: data['timestamp'] as Timestamp,
      readBy: List<String>.from(data['readBy'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      "chatRoomId": chatRoomId,
      "senderId": senderId,
      "receiverId": receiverId,
      "content": content,
      "type": type.toString().split('.').last,
      "status": status.toString(),
      "timestamp": timestamp,
      "readBy": readBy,
      'reactions': reactions,
      'userReactions': userReactions,
    };
   if (replyToMessageId != null) {
      map['replyTo'] = {
        'messageId': replyToMessageId,
        'content': replyToContent,
        'type': replyToType!.toString().split('.').last,
      };
    }

    return map;
  }

  ChatMessage copyWith({
    String? id,
    String? chatRoomId,
    String? senderId,
    String? receiverId,
    String? content,
    MessageType? type,
    MessageStatus? status,
    Timestamp? timestamp,
    List<String>? readBy,
    String? replyToMessageId,
    String? replyToContent,
    MessageType? replyToType,

  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      readBy: readBy ?? this.readBy,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToType: replyToType ?? this.replyToType,
    );
  }
}
