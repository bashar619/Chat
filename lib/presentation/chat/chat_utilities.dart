// lib/presentation/caht/chat_utilities.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';

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

