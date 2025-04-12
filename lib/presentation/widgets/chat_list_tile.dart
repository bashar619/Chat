// lib/presentation/widgets/chat_list_tile.dart
import 'package:flutter/material.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';
import 'package:youtube_messenger_app/data/models/chat_room_model.dart';
import 'package:youtube_messenger_app/data/repositories/chat_repository.dart';
import 'package:youtube_messenger_app/data/services/service_locator.dart';

class ChatListTile extends StatelessWidget {
  final ChatRoomModel chat;
  final String currentUserId;
  final VoidCallback onTap;
  const ChatListTile({
    super.key,
    required this.chat,
    required this.currentUserId,
    required this.onTap,
  });

  String _getOtherUsername() {
    try {
      final otherUserId = chat.participants.firstWhere(
        (id) => id != currentUserId,
        orElse: () => 'Unknown User',
      );
      return chat.participantsName?[otherUserId] ?? "Unknown User";
    } catch (e) {
      return "Unknown User";
    }
  }

  @override
  Widget build(BuildContext context) {
    String displayText;

    // 1) If the last message itself was deleted, show the placeholder
    if (chat.lastMessageType == MessageType.deleted) {
      displayText = chat.lastMessage ?? 'A message has been deleted';

    // 2) Otherwise if it’s a non‑text attachment, show its type
    } else if (chat.lastMessageType != null &&
               chat.lastMessageType != MessageType.text) {
      switch (chat.lastMessageType!) {
        case MessageType.image:
          displayText = "Image";
          break;
        case MessageType.video:
          displayText = "Video";
          break;
        case MessageType.voice:
          displayText = "Voice Message";
          break;
        case MessageType.document:
          displayText = "Document";
          break;
        case MessageType.mediaCollection:
          displayText = "Media";
          break;
        default:
          displayText = "Attachment";
      }

    // 3) Otherwise it’s plain text (or null), so show it directly
    } else {
      displayText = chat.lastMessage ?? "";
    }

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
        child: Text(_getOtherUsername()[0].toUpperCase()),
      ),
      title: Text(
        _getOtherUsername(),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        displayText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600]),
      ),
      trailing: StreamBuilder<int>(
        stream: getIt<ChatRepository>()
            .getUnreadCount(chat.id, currentUserId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == 0) {
            return const SizedBox();
          }
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              snapshot.data.toString(),
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      ),
    );
  }
}
