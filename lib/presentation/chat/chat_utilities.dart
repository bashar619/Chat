// lib/presentation/caht/chat_utilities.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';
import 'package:youtube_messenger_app/logic/cubits/chat/chat_cubit.dart';
import 'package:youtube_messenger_app/presentation/chat/Message_bubble.dart';

class MediaPreviewSheet extends StatelessWidget {
  final List<File> files;
  const MediaPreviewSheet({required this.files});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 350,
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              itemCount: files.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (_, i) {
                final file = files[i];
                final ext = file.path.split('.').last.toLowerCase();
                if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(color: Colors.black12),
                      Icon(Icons.videocam, size: 40),
                    ],
                  );
                }
                return Image.file(file, fit: BoxFit.cover);
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send'),
              ),
            ],
          )
        ],
      ),
    );
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
}


class CacheMessageWidget extends StatefulWidget {
  final ChatMessage message;
  final bool isMe;
  final Function(ChatMessage) onReply;
  final ChatCubit chatCubit;

  const CacheMessageWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.chatCubit,
  });

  @override
  State<CacheMessageWidget> createState() => _CacheMessageWidgetState();
}

class _CacheMessageWidgetState extends State<CacheMessageWidget> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MessageBubble(
          message: widget.message,
          isMe: widget.isMe,
          chatCubit: widget.chatCubit,
          onReply: widget.onReply,
        ),
        if (widget.message.reactions.isNotEmpty)
          const SizedBox(height: 20),
      ],
    );
  }
}
