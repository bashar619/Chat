// lib/presentation/chat/chat_functions.dart
import 'package:flutter/material.dart';

class ReactionWidget extends StatelessWidget {
  final void Function(String) onReactionSelected;

  const ReactionWidget({Key? key, required this.onReactionSelected})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<String> reactions = ['❤️', '😂', '😮', '😢', '👍', '👎'];
    final size = MediaQuery.of(context).size;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.02),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: reactions.map((emoji) {
          return IconButton(
            icon: Text(
              emoji,
              style: TextStyle(fontSize: size.height * 0.03),
            ),
            onPressed: () => onReactionSelected(emoji),
          );
        }).toList(),
      ),
    );
  }
}