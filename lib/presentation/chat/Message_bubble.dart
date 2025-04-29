// lib/presentation/chat/Message_bubble.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:youtube_messenger_app/logic/cubits/chat/chat_cubit.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';
import 'media_handler.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final ChatCubit chatCubit;
  final Function(ChatMessage) onReply;
  final GlobalKey _key = GlobalKey();

  MessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
    required this.chatCubit,
    required this.onReply,
  }) : super(key: key);

  // for getting reply type of content displayed in the message bubble
  String _getReplyDisplayText(ChatMessage message) {
    String prefix = 'Replying to: ';
    switch (message.type) {
      case MessageType.image:
        return '${prefix}📷 Image';
      case MessageType.video:
        return '${prefix}🎥 Video';
      case MessageType.voice:
        return '${prefix}🎤 Voice Message';
      case MessageType.document:
        return '${prefix}📄 Document';
      case MessageType.mediaCollection:
        return '${prefix}🖼️ Media Collection';
      case MessageType.text:
      default:
        return prefix + message.content;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget contentWidget;

    //handle deleted placeholder
    if (message.type == MessageType.deleted) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            left: isMe ? 64 : 8,
            right: isMe ? 8 : 64,
            bottom: 4,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'A message has been deleted',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      );
    }

    switch (message.type) {
      case MessageType.image:
        contentWidget = GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullMediaViewer(urls: [message.content]),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              message.content,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
        );
        break;

      case MessageType.voice:
        contentWidget = AudioBubble(
          url: message.content,
          isMe: isMe,
        );
        break;

      case MessageType.video:
        contentWidget = VideoBubble(
          url: message.content,
          key: ValueKey(message.id),
        );
        break;

      case MessageType.mediaCollection:
        final urls = List<String>.from(jsonDecode(message.content));
        final count = urls.length;
        final display = count > 4 ? urls.sublist(0, 3) : urls;

        contentWidget = SizedBox(
          width: 200,
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (int i = 0; i < display.length; i++)
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FullMediaViewer(urls: urls, initialIndex: i),
                    ),
                  ),
                  child: _buildGridTile(display[i]),
                ),
              if (count > 4)
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FullMediaViewer(urls: urls, initialIndex: 3),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildGridTile(urls[3]),
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Text(
                            '+${count - 4}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
        break;

      default:
        contentWidget = Text(
          message.content,
          style: TextStyle(color: Colors.black),
        );
    }

    return GestureDetector(
      key: _key,
      onLongPress: () => _showReactionsAndOptions(context),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            left: isMe ? 64 : 8,
            right: isMe ? 8 : 64,
            bottom: 4,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (message.replyToMessageId != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.white24 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _getReplyDisplayText(message),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: isMe ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    contentWidget,
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('h:mm a')
                              .format(message.timestamp.toDate()),
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.done_all,
                            size: 14,
                            color: message.status == MessageStatus.read
                                ? Colors.red
                                : Colors.black45,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (message.reactions.isNotEmpty)
                Positioned(
                  bottom: -10,
                  right: isMe ? null : 8,
                  left: isMe ? 8 : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: message.reactions.entries.map((entry) {
                        final emoji = entry.key;
                        final count = entry.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                emoji,
                                style: const TextStyle(fontSize: 14),
                              ),
                              if (count > 1) ...[
                                const SizedBox(width: 2),
                                Text(
                                  count.toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReactionsAndOptions(BuildContext context) {
    final reactions = ['❤️', '😂', '😮', '😢', '👍', '👎'];
    final size = MediaQuery.of(context).size;

    // Get the position of the message bubble
    final RenderBox renderBox =
        _key.currentContext!.findRenderObject() as RenderBox;
    final Size bubbleSize = renderBox.size;
    final Offset bubblePosition = renderBox.localToGlobal(Offset.zero);

    // Calculate the target position (center of screen)
    final double targetY = (size.height - bubbleSize.height) / 2;
    final double moveDistance = targetY - bubblePosition.dy;

    // Create an overlay entry for the animated message and reactions
    late OverlayEntry messageOverlay;

    void removeOverlay() {
      if (messageOverlay.mounted) {
        messageOverlay.remove();
      }
    }

    messageOverlay = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          // Darkened background
          Positioned.fill(
            child: GestureDetector(
              onTapDown: (_) => removeOverlay(),
              child: Container(
                color: Colors.black.withOpacity(0.4),
              ),
            ),
          ),

          // Animated message bubble
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            top: targetY,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  height: size.height * 0.8,
                  width: size.width * 0.8,
                  child: Center(
                    child: Expanded(
                      child: buildMessageContent(),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Reactions menu
          Positioned(
            top: targetY - 60, // Position above the message
            left: (size.width - (size.width * 0.60)) / 2, // Center horizontally
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: size.width * 0.60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      offset: Offset(0, 2),
                      blurRadius: 8,
                      color: Colors.black.withOpacity(0.2),
                    ),
                  ],
                ),
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: reactions.map((emoji) {
                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: GestureDetector(
                            onTap: () {
                              chatCubit.addReaction(
                                messageId: message.id,
                                emoji: emoji,
                              );
                              removeOverlay();
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                emoji,
                                style: TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Insert the overlay
    Overlay.of(context).insert(messageOverlay);

    // Show options bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        final isText = message.type == MessageType.text;
        final isMe = message.senderId == chatCubit.currentUserId;

        return SafeArea(
          child: Wrap(
            children: [
              if (isText)
                _buildAnimatedOption(
                  icon: Icons.copy,
                  title: 'Copy',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    removeOverlay();
                    Navigator.pop(bottomSheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Message copied')),
                    );
                  },
                ),
              _buildAnimatedOption(
                icon: Icons.reply,
                title: 'Reply',
                onTap: () {
                  removeOverlay();
                  Navigator.pop(bottomSheetContext);
                  onReply(message);
                },
              ),
              if (isMe && isText)
                _buildAnimatedOption(
                  icon: Icons.edit,
                  title: 'Edit',
                  onTap: () {
                    removeOverlay();
                    Navigator.pop(bottomSheetContext);
                    _showEditDialog(context);
                  },
                ),
              if (isMe)
                _buildAnimatedOption(
                  icon: Icons.delete_forever,
                  title: 'Unsend',
                  isDestructive: true,
                  onTap: () {
                    removeOverlay();
                    Navigator.pop(bottomSheetContext);
                    chatCubit.deleteMessage(message.id);
                  },
                ),
              _buildAnimatedOption(
                icon: Icons.close,
                title: 'Cancel',
                onTap: () {
                  removeOverlay();
                  Navigator.pop(bottomSheetContext);
                },
              ),
            ],
          ),
        );
      },
    ).then((_) => removeOverlay());
  }

  // Helper method to build the message content
  Widget buildMessageContent() {
    return Container(
      margin: EdgeInsets.only(
        left: isMe ? 64 : 8,
        right: isMe ? 8 : 64,
        bottom: 4,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.replyToMessageId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getReplyDisplayText(message),
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
              ),
            ),
          if (message.type == MessageType.text)
            Text(message.content)
          else if (message.type == MessageType.image)
            Image.network(message.content,
                width: 200, height: 200, fit: BoxFit.cover)
          else if (message.type == MessageType.video)
            VideoBubble(key: ValueKey(message.id), url: message.content)
          else if (message.type == MessageType.voice)
            AudioBubble(url: message.content, isMe: isMe)
          else
            Text(message.content),
          const SizedBox(height: 4),
          Text(
            DateFormat('h:mm a').format(message.timestamp.toDate()),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // edit message
  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty && newText != message.content) {
                chatCubit.editMessage(
                  messageId: message.id,
                  newContent: newText,
                );
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 20),
          child: ListTile(
            leading: Icon(
              icon,
              color: isDestructive ? Colors.red : null,
            ),
            title: Text(
              title,
              style: TextStyle(
                color: isDestructive ? Colors.red : null,
              ),
            ),
            onTap: onTap,
          ),
        );
      },
    );
  }
}

//multipile media gridview handler
Widget _buildGridTile(String url) {
  final isVideo = url.toLowerCase().endsWith('.mp4');
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.network(url, fit: BoxFit.cover),
        if (isVideo)
          const Center(
              child: Icon(Icons.play_circle_outline,
                  size: 40, color: Colors.white70)),
      ],
    ),
  );
}

class _WaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB2DFDB)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Draw static bars
    final barCount = 20;
    final barWidth = size.width / (barCount * 1.5);
    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth * 1.5 + barWidth / 2;
      final barHeight = size.height * (0.3 + 0.7 * (i % 2 == 0 ? 0.7 : 0.4));
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
