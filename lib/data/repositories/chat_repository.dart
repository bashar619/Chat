// lib/data/repositories/chat_repositories/chat_repositories.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';
import 'package:youtube_messenger_app/data/models/chat_room_model.dart';
import 'package:youtube_messenger_app/data/models/user_model.dart';
import 'package:youtube_messenger_app/data/services/base_repository.dart';

class ChatRepository extends BaseRepository {
  CollectionReference get _chatRooms => firestore.collection("chatRooms");

  CollectionReference getChatRoomMessages(String chatRoomId) {
    return _chatRooms.doc(chatRoomId).collection("messages");
  }

  Future<ChatRoomModel> getOrCreateChatRoom(
      String currentUserId, String otherUserId) async {
    // Prevent creating a chat room with yourself
    if (currentUserId == otherUserId) {
      throw Exception("Cannot create a chat room with yourself");
    }

    final users = [currentUserId, otherUserId]..sort();
    final roomId = users.join("_");

    final roomDoc = await _chatRooms.doc(roomId).get();

    if (roomDoc.exists) {
      return ChatRoomModel.fromFirestore(roomDoc);
    }

    final currentUserData =
        (await firestore.collection("users").doc(currentUserId).get()).data()
            as Map<String, dynamic>;
    final otherUserData =
        (await firestore.collection("users").doc(otherUserId).get()).data()
            as Map<String, dynamic>;
    final participantsName = {
      currentUserId: currentUserData['fullName']?.toString() ?? "",
      otherUserId: otherUserData['fullName']?.toString() ?? "",
    };

    final newRoom = ChatRoomModel(
        id: roomId,
        participants: users,
        participantsName: participantsName,
        lastReadTime: {
          currentUserId: Timestamp.now(),
          otherUserId: Timestamp.now(),
        });

    await _chatRooms.doc(roomId).set(newRoom.toMap());
    return newRoom;
  }

  Future<void> sendMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String content,
    MessageType type = MessageType.text,
    String? replyToMessageId,
    String? replyToContent,
    MessageType? replyToType,
  }) async {
    //start a firebase batch
    final batch = firestore.batch();

    //get message sub collection

    final messageRef = getChatRoomMessages(chatRoomId);
    final messageDoc = messageRef.doc();

    //chatmessage

    final message = ChatMessage(
      id: messageDoc.id,
      chatRoomId: chatRoomId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      type: type,
      timestamp: Timestamp.now(),
      readBy: [senderId],
      replyToMessageId: replyToMessageId,
      replyToContent: replyToContent,
      replyToType: replyToType,
      userReactions: {},
    );

    // Determine the display text for the last message.
    String displayMessage;
    switch (type) {
      case MessageType.text:
        displayMessage = content;
        break;
      case MessageType.image:
        displayMessage = "📷Image";
        break;
      case MessageType.video:
        displayMessage = "🎥Video";
        break;
      case MessageType.voice:
        displayMessage = "🎤Voice Message";
        break;
      case MessageType.document:
        displayMessage = "📄Document";
        break;
      case MessageType.mediaCollection:
        displayMessage = "🖼️Media";
        break;
      default:
        displayMessage = "Attachment";
        break;
    }

    //add message to sub collection
    batch.set(messageDoc, message.toMap());

    //update chatroom

    batch.update(_chatRooms.doc(chatRoomId), {
      "lastMessage": displayMessage,
      "lastMessageSenderId": senderId,
      "lastMessageTime": message.timestamp,
      "lastMessageType": type.toString().split('.').last,
    });
    await batch.commit();
  }

  //a--> b
  Stream<List<ChatMessage>> getMessages(String chatRoomId,
      {DocumentSnapshot? lastDocument}) {
    var query = getChatRoomMessages(chatRoomId)
        .orderBy('timestamp', descending: true)
        .limit(20);

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList());
  }

  Future<List<ChatMessage>> getMoreMessages(String chatRoomId,
      {required DocumentSnapshot lastDocument}) async {
    final query = getChatRoomMessages(chatRoomId)
        .orderBy('timestamp', descending: true)
        .startAfterDocument(lastDocument)
        .limit(20);
    print("comingg");
    final snapshot = await query.get();
    return snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList();
  }

  Stream<List<ChatRoomModel>> getChatRooms(String userId) {
    return _chatRooms
        .where("participants", arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatRoomModel.fromFirestore(doc))
            .toList());
  }

  Stream<int> getUnreadCount(String chatRoomId, String userId) {
    return getChatRoomMessages(chatRoomId)
        .where("receiverId", isEqualTo: userId)
        .where('status', isEqualTo: MessageStatus.sent.toString())
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markMessagesAsRead(String chatRoomId, String userId) async {
  try {
    final batch = firestore.batch();

    // Get all unread messages where the user is the receiver.
    final unreadMessages = await getChatRoomMessages(chatRoomId)
        .where("receiverId", isEqualTo: userId)
        .where('status', isEqualTo: MessageStatus.sent.toString())
        .get();

    print("found ${unreadMessages.docs.length} unread messages");

    // Queue up each message update in the batch.
    for (final doc in unreadMessages.docs) {
      batch.update(doc.reference, {
        'readBy': FieldValue.arrayUnion([userId]),
        'status': MessageStatus.read.toString(),
      });
    } 

    // Commit all the message updates.
    await batch.commit();

    // Update the room's lastReadTime for this user.
    await _chatRooms.doc(chatRoomId).update({
      'lastReadTime.$userId': Timestamp.now(),
    });

    print("Updated lastReadTime for user $userId in room $chatRoomId");
  } catch (e) {
    print("Error marking messages as read: $e");
  }
}

  Future<void> deleteMessage({
    required String chatRoomId,
    required String messageId,
  }) async {
    final roomRef = _chatRooms.doc(chatRoomId);
    final msgRef = getChatRoomMessages(chatRoomId).doc(messageId);

    // First get the original message content
    final msgDoc = await msgRef.get();
    final msgData = msgDoc.data() as Map<String, dynamic>;
    final originalContent = msgData['content'] as String;

    // Mark the target message as deleted while preserving original content
    await msgRef.update({
      'content': 'A message has been deleted',
      'originalContent': originalContent, // Store the original content
      'type': MessageType.deleted.toString().split('.').last,
      'reactions': {},
      'userReactions': {},
    });

    // 2) fetch exactly the most‐recent message in this room
    final snap = await getChatRoomMessages(chatRoomId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      // no messages at all (shouldn't really happen), just clear
      await roomRef.update({
        'lastMessage': '',
        'lastMessageSenderId': null,
        'lastMessageTime': null,
        'lastMessageType': null,
      });
      return;
    }

    // 3) build our ChatMessage model
    final lastMsg = ChatMessage.fromFirestore(snap.docs.first);

    // 4) pick the display text
    final display = _displayForType(lastMsg);

    // 5) write it back into the room
    await roomRef.update({
      'lastMessage': display,
      'lastMessageSenderId': lastMsg.senderId,
      'lastMessageTime': lastMsg.timestamp,
      'lastMessageType': lastMsg.type.toString().split('.').last,
    });
  }

  /// helper that even returns the deletion placeholder
  String _displayForType(ChatMessage m) {
    switch (m.type) {
      case MessageType.text:
        return m.content;
      case MessageType.image:
        return '📷 Image';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.voice:
        return '🎤 Voice Message';
      case MessageType.document:
        return '📄 Document';
      case MessageType.mediaCollection:
        return '🖼️ Media';
      case MessageType.deleted:
        return 'A message has been deleted';
    }
  }

  Stream<Map<String, dynamic>> getUserOnlineStatus(String userId) {
    return firestore
        .collection("users")
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      return {
        'isOnline': data?['isOnline'] ?? false,
        'lastSeen': data?['lastSeen'],
      };
    });
  }

  Future<void> updateOnlineStatus(String userId, bool isOnline) async {
    await firestore.collection("users").doc(userId).update({
      'isOnline': isOnline,
      'lastSeen': Timestamp.now(),
    });
  }

  Future<void> updateTypingStatus(
      String chatRoomId, String userId, bool isTyping) async {
    try {
      final doc = await _chatRooms.doc(chatRoomId).get();
      if (!doc.exists) {
        print("chat room does not exist");
        return;
      }
      await _chatRooms.doc(chatRoomId).update({
        'isTyping': isTyping,
        'typingUserId': isTyping ? userId : null,
      });
    } catch (e) {
      print("error updating typing status");
    }
  }

  Stream<Map<String, dynamic>> getTypingStatus(String chatRoomId) {
    return _chatRooms.doc(chatRoomId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return {
          'isTyping': false,
          'typingUserId': null,
        };
      }
      final data = snapshot.data() as Map<String, dynamic>;
      return {
        "isTyping": data['isTyping'] ?? false,
        "typingUserId": data['typingUserId'],
      };
    });
  }

  Future<void> blockUser(String currentUserId, String blockedUserId) async {
    final userRef = firestore.collection("users").doc(currentUserId);
    await userRef.update({
      'blockedUsers': FieldValue.arrayUnion([blockedUserId])
    });
  }

  Future<void> unBlockUser(String currentUserId, String blockedUserId) async {
    final userRef = firestore.collection("users").doc(currentUserId);
    await userRef.update({
      'blockedUsers': FieldValue.arrayRemove([blockedUserId])
    });
  }

  Stream<bool> isUserBlocked(String currentUserId, String otherUserId) {
    return firestore
        .collection("users")
        .doc(currentUserId)
        .snapshots()
        .map((doc) {
      final userData = UserModel.fromFirestore(doc);
      return userData.blockedUsers.contains(otherUserId);
    });
  }

  Stream<bool> amIBlocked(String currentUserId, String otherUserId) {
    return firestore
        .collection("users")
        .doc(otherUserId)
        .snapshots()
        .map((doc) {
      final userData = UserModel.fromFirestore(doc);
      return userData.blockedUsers.contains(currentUserId);
    });
  }

  /// Update a message's text
  Future<void> editMessage({
    required String chatRoomId,
    required String messageId,
    required String newContent,
  }) {
    return getChatRoomMessages(chatRoomId)
        .doc(messageId)
        .update({'content': newContent});
  }

  // Message reaction
  Future<void> addReaction({
    required String chatRoomId,
    required String messageId,
    required String userId,
    required String emoji,
  }) {
    final docRef = getChatRoomMessages(chatRoomId).doc(messageId);
    return firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};

      // load existing maps
      final reactions = Map<String, int>.from(data['reactions'] ?? {});
      final userReactions =
          Map<String, String>.from(data['userReactions'] ?? {});

      final oldEmoji = userReactions[userId];
      if (oldEmoji == emoji) {
        // user tapped same emoji → remove reaction
        userReactions.remove(userId);
        reactions[emoji] = (reactions[emoji] ?? 1) - 1;
        if (reactions[emoji]! <= 0) reactions.remove(emoji);
      } else {
        // remove old if present
        if (oldEmoji != null) {
          reactions[oldEmoji] = (reactions[oldEmoji] ?? 1) - 1;
          if (reactions[oldEmoji]! <= 0) reactions.remove(oldEmoji);
        }
        // add new
        userReactions[userId] = emoji;
        reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      }

      tx.update(docRef, {
        'reactions': reactions,
        'userReactions': userReactions,
      });
    });
  }
}
