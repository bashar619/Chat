// lib/presentaion/chat/chat_message_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';
import 'package:youtube_messenger_app/data/services/service_locator.dart';
import 'package:youtube_messenger_app/logic/cubits/chat/chat_cubit.dart';
import 'package:youtube_messenger_app/logic/cubits/chat/chat_state.dart';
import 'package:youtube_messenger_app/presentation/widgets/loading_dots.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';

class ChatMessageScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  const ChatMessageScreen(
      {super.key, required this.receiverId, required this.receiverName});

  @override
  State<ChatMessageScreen> createState() => _ChatMessageScreenState();
}

class _ChatMessageScreenState extends State<ChatMessageScreen> {
  ChatMessage? _replyingTo;
  final TextEditingController messageController = TextEditingController();
  late final ChatCubit _chatCubit;
  final _scrollController = ScrollController();
  List<ChatMessage> _previousMessages = [];
  bool _isComposing = false;
  bool _showEmoji = false;
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  //start recording on press
  Future<void> _startVoiceRecording() async {
    if (_isRecording) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/${const Uuid().v4()}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
      ),
      path: path,
    );
    setState(() => _isRecording = true);
  }

  // send on release
  Future<void> _stopVoiceRecording() async {
    if (!_isRecording) return;
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path != null) {
      final file = File(path);
      final fileName = const Uuid().v4();
      final ref =
          FirebaseStorage.instance.ref().child('voiceMessages/$fileName.m4a');
      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      await _chatCubit.sendMessage(
        content: downloadUrl,
        receiverId: widget.receiverId,
        type: MessageType.voice,
      );
    }
  }

  Future<void> _handleGalleryAttachment() async {
    Navigator.of(context).pop();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
    );
    if (result == null) return;

    final files = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    final shouldSend = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _MediaPreviewSheet(files: files),
        ) ??
        false;

    if (!shouldSend) return;

    // Upload all files in parallel
    final urls = await Future.wait(files.map((file) async {
      final ext = file.path.split('.').last;
      final ref =
          FirebaseStorage.instance.ref().child('chatMedia/${Uuid().v4()}.$ext');
      final task = await ref.putFile(file);
      return await task.ref.getDownloadURL();
    }));

    // Send ONE message containing all URLs
    await _chatCubit.sendMessage(
      content: jsonEncode(urls),
      receiverId: widget.receiverId,
      type: MessageType.mediaCollection,
    );
  }

  Future<void> _uploadAndSendFile(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final type = ['mp4', 'mov', 'avi', 'mkv'].contains(ext)
        ? MessageType.video
        : MessageType.image;

    final ref =
        FirebaseStorage.instance.ref().child('chatMedia/${Uuid().v4()}.$ext');
    final uploadTask = await ref.putFile(file);
    final url = await uploadTask.ref.getDownloadURL();

    await _chatCubit.sendMessage(
      content: url,
      receiverId: widget.receiverId,
      type: type,
    );
  }

  @override
  void initState() {
    _chatCubit = getIt<ChatCubit>();
    print("recervier id ${widget.receiverId}");
    _chatCubit.enterChat(widget.receiverId);
    messageController.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
    super.initState();
  }

  Future<void> _handleSendMessage() async {
    final messageText = messageController.text.trim();
    if (messageText.isEmpty) return;
    final reply = _replyingTo;
    messageController.clear();
    setState(() => _replyingTo = null);

    await _chatCubit.sendMessage(
      content: messageText,
      receiverId: widget.receiverId,
      // forward the reply info
      replyToMessageId: reply?.id,
      replyToContent: reply?.content,
      replyToType: reply?.type,
    );
  }

  Future<void> _handleVoiceMessage() async {
    if (!_isRecording) {
      // Start recording
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${const Uuid().v4()}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
        ),
        path: path,
      );

      setState(() {
        _isRecording = true;
      });
    } else {
      // Stop and send recording
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (path != null) {
        final file = File(path);
        final fileName = const Uuid().v4();
        final ref =
            FirebaseStorage.instance.ref().child('voiceMessages/$fileName.m4a');
        final uploadTask = await ref.putFile(file);
        final downloadUrl = await uploadTask.ref.getDownloadURL();

        // Send audio message as URL
        await _chatCubit.sendMessage(
          content: downloadUrl,
          receiverId: widget.receiverId,
          type: MessageType.voice,
        );
      }
    }
  }

  void _onScroll() {
    //load more messages when reaching to top

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _chatCubit.loadMoreMessages();
    }
  }

  void _onTextChanged() {
    final isComposing = messageController.text.isNotEmpty;
    if (isComposing != _isComposing) {
      setState(() {
        _isComposing = isComposing;
      });
      if (isComposing) {
        _chatCubit.startTyping();
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _hasNewMessages(List<ChatMessage> messages) {
    if (messages.length != _previousMessages.length) {
      _scrollToBottom();
      _previousMessages = messages;
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    _scrollController.dispose();
    _chatCubit.leaveChat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Text(widget.receiverName[0].toUpperCase()),
            ),
            const SizedBox(
              width: 12,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.receiverName),
                BlocBuilder<ChatCubit, ChatState>(
                    bloc: _chatCubit,
                    builder: (context, state) {
                      if (state.isReceiverTyping) {
                        return Row(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 4),
                              child: const LoadingDots(),
                            ),
                            Text(
                              "typing",
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                              ),
                            )
                          ],
                        );
                      }
                      if (state.isReceiverOnline) {
                        return const Text(
                          "Online",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.green,
                          ),
                        );
                      }
                      if (state.receiverLastSeen != null) {
                        final lastSeen = state.receiverLastSeen!.toDate();
                        return Text(
                          "last seen at ${DateFormat('h:mm a').format(lastSeen)}",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        );
                      }
                      return const SizedBox();
                    })
              ],
            ),
          ],
        ),
        actions: [
          BlocBuilder<ChatCubit, ChatState>(
              bloc: _chatCubit,
              builder: (context, state) {
                if (state.isUserBlocked) {
                  return TextButton.icon(
                    onPressed: () => _chatCubit.unBlockUser(widget.receiverId),
                    label: const Text(
                      "Unblock",
                    ),
                    icon: const Icon(Icons.block),
                  );
                }
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    if (value == "block") {
                      final bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                              "Are you sure you want to block ${widget.receiverName}"),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  "Block",
                                  style: TextStyle(color: Colors.red),
                                ))
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _chatCubit.blockUser(widget.receiverId);
                      }
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem(
                      value: 'block',
                      child: Text("Block User"),
                    )
                  ],
                );
              })
        ],
      ),
      body: BlocConsumer<ChatCubit, ChatState>(
        listener: (context, state) {
          _hasNewMessages(state.messages);
        },
        bloc: _chatCubit,
        builder: (context, state) {
          if (state.status == ChatStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == ChatStatus.error) {
            Center(
              child: Text(state.error ?? "Something went wrong"),
            );
          }
          return Column(
            children: [
              if (state.amIBlocked)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.withOpacity(0.1),
                  child: Text(
                    "You have been blocked by ${widget.receiverName}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final message = state.messages[index];
                    final isMe = message.senderId == _chatCubit.currentUserId;
                    return Dismissible(
                      key: Key(message.id),
                      direction: DismissDirection.startToEnd,
                      background: Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.reply, color: Colors.grey),
                      ),
                      confirmDismiss: (dir) async {
                        setState(() => _replyingTo = message);
                        return false;
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MessageBubble(
                            message: message,
                            isMe: isMe,
                            chatCubit: _chatCubit,
                            onReply: (msg) => setState(() => _replyingTo = msg),
                          ),
                          if (message.reactions.isNotEmpty)
                            const SizedBox(height: 20),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (!state.amIBlocked && !state.isUserBlocked)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      if (_replyingTo != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Replying to: ${_replyingTo!.content}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () =>
                                    setState(() => _replyingTo = null),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.attach_file,
                              color: const Color.fromARGB(255, 148, 163, 184),
                              size: size.height * 0.03,
                            ),
                            onPressed: _handleAttachmentPressed,
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          Expanded(
                            child: TextField(
                              onTap: () {
                                if (_showEmoji) {
                                  setState(() {
                                    _showEmoji = false;
                                  });
                                }
                              },
                              controller: messageController,
                              textCapitalization: TextCapitalization.sentences,
                              keyboardType: TextInputType.multiline,
                              decoration: InputDecoration(
                                hintText: "Type a message",
                                filled: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                fillColor: Theme.of(context).cardColor,
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          if (_isComposing)
                            InkWell(
                              onTap: _handleSendMessage,
                              child: Container(
                                child: Icon(Icons.send, color: Colors.white),
                              ),
                            )
                          else
                            GestureDetector(
                              onTapDown: (_) => _startVoiceRecording(),
                              onTapUp: (_) => _stopVoiceRecording(),
                              onTapCancel: () => _stopVoiceRecording(),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Color.fromARGB(255, 144, 29, 35),
                                  shape: BoxShape.circle,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      offset: Offset(0.0, 7.5),
                                      blurRadius: 10,
                                      color: Color.fromARGB(135, 0, 0, 0),
                                    ),
                                  ],
                                ),
                                padding: EdgeInsets.all(size.height * 0.02),
                                child: Icon(
                                  _isRecording ? Icons.mic : Icons.mic_none,
                                  color: Colors.white,
                                  size: size.height * 0.022,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_showEmoji)
                        SizedBox(
                          height: 250,
                          child: EmojiPicker(
                            textEditingController: messageController,
                            onEmojiSelected: (category, emoji) {
                              messageController
                                ..text += emoji.emoji
                                ..selection = TextSelection.fromPosition(
                                  TextPosition(
                                      offset: messageController.text.length),
                                );
                              setState(() {
                                _isComposing =
                                    messageController.text.isNotEmpty;
                              });
                            },
                            config: Config(
                              height: 250,
                              emojiViewConfig: EmojiViewConfig(
                                columns: 7,
                                emojiSizeMax:
                                    32.0 * (Platform.isIOS ? 1.30 : 1.0),
                                verticalSpacing: 0,
                                horizontalSpacing: 0,
                                gridPadding: EdgeInsets.zero,
                                backgroundColor:
                                    Theme.of(context).scaffoldBackgroundColor,
                                loadingIndicator: const SizedBox.shrink(),
                              ),
                              categoryViewConfig: const CategoryViewConfig(
                                initCategory: Category.RECENT,
                              ),
                              bottomActionBarConfig: BottomActionBarConfig(
                                enabled: true,
                                backgroundColor:
                                    Theme.of(context).scaffoldBackgroundColor,
                                buttonColor: Theme.of(context).primaryColor,
                              ),
                              skinToneConfig: const SkinToneConfig(
                                enabled: true,
                                dialogBackgroundColor: Colors.white,
                                indicatorColor: Colors.grey,
                              ),
                              searchViewConfig: SearchViewConfig(
                                backgroundColor:
                                    Theme.of(context).scaffoldBackgroundColor,
                                buttonIconColor: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
            ],
          );
        },
      ),
    );
  }

  // multi documents method
  Future<void> _handleDocumentAttachment() async {
    Navigator.of(context).pop();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null) return;

    for (final picked in result.files) {
      if (picked.path == null) continue;

      final file = File(picked.path!);
      final fileName = '${Uuid().v4()}_${picked.name}';
      final ref = FirebaseStorage.instance.ref().child('documents/$fileName');
      final uploadTask = await ref.putFile(file);
      final url = await uploadTask.ref.getDownloadURL();

      await _chatCubit.sendMessage(
        content: url,
        receiverId: widget.receiverId,
        type: MessageType.document,
      );
    }
  }

  void _handleAttachmentPressed() {
    final size = MediaQuery.of(context).size;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color.fromARGB(255, 248, 245, 238),
                Color.fromARGB(255, 255, 255, 255),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: size.height * 0.004,
                width: size.width * 0.09,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 100, 116, 139),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              SizedBox(height: size.height * 0.006),
              Wrap(
                children: [
                  // Camera Option
                  _buildAttachmentOption(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () async {
                      Navigator.of(context).pop();

                      // 1) Request camera permission
                      final status = await Permission.camera.request();
                      if (status != PermissionStatus.granted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Camera permission denied')),
                        );
                        return;
                      }
                      // 2) Launch camera for photo
                      try {
                        final picker = ImagePicker();
                        final XFile? photo = await picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 85, // optional compression
                          maxWidth: 1280, // optional resizing
                        );
                        if (photo == null) return;

                        // 3) Upload & send
                        final ext = '.jpg';
                        final ref = FirebaseStorage.instance
                            .ref()
                            .child('chatMedia/${Uuid().v4()}$ext');
                        final upload = await ref.putFile(File(photo.path));
                        final url = await upload.ref.getDownloadURL();
                        await _chatCubit.sendMessage(
                          content: url,
                          receiverId: widget.receiverId,
                          type: MessageType.image,
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Camera error: $e')),
                        );
                      }
                    },
                  ),
                  // Gallery Option
                  _buildAttachmentOption(
                    icon: Icons.image,
                    label: 'Gallery',
                    onTap: _handleGalleryAttachment,
                  ),
                  // Document Option using File Picker
                  _buildAttachmentOption(
                    icon: Icons.attachment,
                    label: 'Document',
                    onTap: _handleDocumentAttachment,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final size = MediaQuery.of(context).size;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size.height * 0.075,
            height: size.height * 0.075,
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 244, 231, 232),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: size.height * 0.026,
              color: const Color.fromARGB(255, 144, 29, 35),
            ),
          ),
        ),
        SizedBox(height: size.height * 0.008),
        Text(
          label,
          style: TextStyle(
            fontSize: size.height * 0.014,
            color: const Color.fromARGB(255, 15, 23, 42),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: size.height * 0.01),
      ],
    );
  }
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final ChatCubit chatCubit;
  final void Function(ChatMessage) onReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.chatCubit,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    Widget contentWidget;
    final isMe = message.senderId == chatCubit.currentUserId;

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
        contentWidget = VideoBubble(url: message.content);
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
          style: TextStyle(color: isMe ? Colors.white : Colors.black),
        );
    }
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      onLongPress: () => _showOptions(context),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: const EdgeInsets.only(
                  bottom: 4,
                ),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).primaryColor.withOpacity(0.1),
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
                          message.replyToContent ?? '',
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
                    //timestamp
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('h:mm a')
                              .format(message.timestamp.toDate()),
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.black54,
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
                                : Colors.white70,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                // Emoji under a text message
              ),
              if (message.reactions.isNotEmpty)
                Positioned(
                  bottom: -14,
                  left: isMe ? 8 : null,
                  right: isMe ? null : 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: message.reactions.entries.map((entry) {
                      final emoji = entry.key;
                      final count = entry.value;
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          width: count == 1 ? null : 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(100.0),
                            boxShadow: const [
                              BoxShadow(
                                offset: Offset(0, 0),
                                blurRadius: 8,
                                color: Color.fromARGB(150, 0, 0, 0),
                              ),
                            ],
                          ),
                          padding: EdgeInsets.all(
                              MediaQuery.of(context).size.height * 0.0037),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                emoji,
                                style: TextStyle(
                                  fontSize: MediaQuery.of(context).size.height *
                                      0.018,
                                ),
                              ),
                              if (count > 1) ...[
                                const SizedBox(width: 2),
                                Text(
                                  count.toString(),
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.of(context).size.height *
                                            0.016,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // hold message functionality
  void _showOptions(BuildContext context) {
    final isText = message.type == MessageType.text;

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  onReply(message);
                }),
            if (isMe && isText) // only you can edit
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions),
              title: const Text('React'),
              onTap: () {
                Navigator.pop(context);
                _showReactionPicker(context);
              },
            ),
            if (isMe) // only you can unsend
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title:
                    const Text('Unsend', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  chatCubit.deleteMessage(message.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
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

  void _showReactionPicker(BuildContext context) {
    final emojis = ['👍', '👎', '❤️', '😂', '😮', '😢', '👏'];
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: emojis.map((e) {
            return IconButton(
              icon: Text(e, style: const TextStyle(fontSize: 24)),
              onPressed: () {
                Navigator.pop(context);
                chatCubit.addReaction(
                  messageId: message.id,
                  emoji: e,
                );
              },
            );
          }).toList(),
        ),
      ),
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

class FullMediaViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const FullMediaViewer({
    Key? key,
    required this.urls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  _FullMediaViewerState createState() => _FullMediaViewerState();
}

class _FullMediaViewerState extends State<FullMediaViewer> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (context, i) {
          final url = widget.urls[i];
          final isVideo = url.toLowerCase().endsWith('.mp4');
          return Center(
            child: isVideo
                ? VideoBubble(url: url)
                : Image.network(url, fit: BoxFit.contain),
          );
        },
      ),
    );
  }
}

// video handler
class VideoBubble extends StatefulWidget {
  final String url;
  const VideoBubble({super.key, required this.url});

  @override
  _VideoBubbleState createState() => _VideoBubbleState();
}

class _MediaPreviewSheet extends StatelessWidget {
  final List<File> files;
  const _MediaPreviewSheet({required this.files});

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
}

class AudioBubble extends StatefulWidget {
  final String url;
  final bool isMe;
  const AudioBubble({
    Key? key,
    required this.url,
    this.isMe = false,
  }) : super(key: key);

  @override
  _AudioBubbleState createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  late final AudioPlayer _player;
  Duration _total = Duration.zero;
  Duration _position = Duration.zero;
  PlayerState _state = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer()
      ..onPlayerStateChanged.listen((s) {
        setState(() => _state = s);
      })
      ..onDurationChanged.listen((d) {
        setState(() => _total = d);
      })
      ..onPositionChanged.listen((p) {
        setState(() => _position = p);
      });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // white icon on sent bubbles, primaryColor on received
    final iconColor =
        widget.isMe ? Colors.white : Theme.of(context).primaryColor;
    // progress bar color
    final progressColor =
        widget.isMe ? Colors.white70 : Theme.of(context).primaryColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play/Pause button
        IconButton(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          iconSize: 32,
          icon: Icon(
            _state == PlayerState.playing
                ? Icons.pause_circle_filled
                : Icons.play_circle_outline,
            color: iconColor,
          ),
          onPressed: () {
            if (_state == PlayerState.playing) {
              _player.pause();
            } else {
              _player.play(UrlSource(widget.url));
            }
          },
        ),

        // Slider + timestamps
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 4),
                  thumbColor: progressColor,
                  activeTrackColor: progressColor,
                  inactiveTrackColor: progressColor.withOpacity(0.4),
                ),
                child: Slider(
                  min: 0,
                  max: _total.inMilliseconds
                      .toDouble()
                      .clamp(1, double.infinity),
                  value: _position.inMilliseconds
                      .clamp(0, _total.inMilliseconds)
                      .toDouble(),
                  onChanged: (value) {
                    final seekPos = Duration(milliseconds: value.toInt());
                    _player.seek(seekPos);
                  },
                ),
              ),

              // Position / Duration text
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _format(_position),
                    style: TextStyle(
                      fontSize: 12,
                      color: iconColor.withOpacity(0.9),
                    ),
                  ),
                  Text(
                    _format(_total),
                    style: TextStyle(
                      fontSize: 12,
                      color: iconColor.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

//i forgot what does this do sorry

class _VideoBubbleState extends State<VideoBubble> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onTap: () => _controller.value.isPlaying
          ? _controller.pause()
          : _controller.play(),
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      ),
    );
  }
}
