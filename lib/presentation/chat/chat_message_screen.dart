// lib/presentaion/chat/chat_message_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:youtube_messenger_app/presentation/chat/chat_functions.dart';
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
  DateTime? _cameraPressStart;
  OverlayEntry? _emojiOverlayEntry;

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

    // Let user preview & confirm
    final shouldSend = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _MediaPreviewSheet(files: files),
        ) ??
        false;
    if (!shouldSend) return;

    if (files.length == 1) {
      // Single file → treat as individual image/video
      await _uploadAndSendFile(files.first);
    } else {
      // Multiple files → bundle as mediaCollection
      final urls = await Future.wait(files.map((file) async {
        final ext = file.path.split('.').last;
        final ref = FirebaseStorage.instance
            .ref()
            .child('chatMedia/${Uuid().v4()}.$ext');
        final task = await ref.putFile(file);
        return await task.ref.getDownloadURL();
      }));

      await _chatCubit.sendMessage(
        content: jsonEncode(urls),
        receiverId: widget.receiverId,
        type: MessageType.mediaCollection,
      );
    }
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
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required for voice messages')),
      );
      return;
    }

    if (!_isRecording) {
      try {
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
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    } else {
      try {
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
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop recording: $e')),
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
                    Widget messageWidget = Column(
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
                    );

                    return message.type == MessageType.deleted
                      ? messageWidget
                      : Dismissible(
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
                          child: messageWidget,
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
                                  _getReplyDisplayText(_replyingTo!),
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
                          const SizedBox(width: 8),
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
                          const SizedBox(width: 8),
                          if (_isComposing)
                            InkWell(
                              onTap: _handleSendMessage,
                              child: Container(
                                padding: EdgeInsets.all(size.height * 0.02),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      offset: Offset(0, 7.5),
                                      blurRadius: 10,
                                      color: Colors.black.withOpacity(0.15),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.send,
                                  color: Colors.white,
                                  size: size.height * 0.022,
                                ),
                              ),
                            )
                          else
                            GestureDetector(
                              onTapDown: (_) => _handleVoiceMessage(),
                              onTapUp: (_) => _handleVoiceMessage(),
                              child: Container(
                                padding: EdgeInsets.all(size.height * 0.02),
                                decoration: BoxDecoration(
                                  color: _isRecording ? Colors.red : Theme.of(context).primaryColor,
                                  shape: BoxShape.circle,
                                ),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Rename the builder's parameter from `context` to `sheetContext`
      builder: (BuildContext sheetContext) {
        final size = MediaQuery.of(context).size;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Wrap(
            spacing: size.width * 0.1,
            runSpacing: size.height * 0.02,
            alignment: WrapAlignment.center,
            children: [
              // PHOTO
              _buildAttachmentOption(
                icon: Icons.camera_alt,
                label: 'Photo',
                onTap: _handleCameraPhoto,
              ),

              // VIDEO
              _buildAttachmentOption(
                icon: Icons.videocam,
                label: 'Video',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _handleCameraVideo();
                },
              ),

              // GALLERY
              _buildAttachmentOption(
                icon: Icons.image,
                label: 'Gallery',
                onTap: _handleGalleryAttachment,
              ),

              // DOCUMENT
              _buildAttachmentOption(
                icon: Icons.insert_drive_file,
                label: 'Document',
                onTap: _handleDocumentAttachment,
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
    VoidCallback? onLongPress,
  }) {
    final size = MediaQuery.of(context).size;
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(size.height * 0.0375),
            child: Container(
              width: size.height * 0.075,
              height: size.height * 0.075,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 244, 231, 232),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: size.height * 0.026,
                  color: Color.fromARGB(255, 144, 29, 35)),
            ),
          ),
        ),
        SizedBox(height: size.height * 0.008),
        Text(label,
            style: TextStyle(
                fontSize: size.height * 0.014,
                color: Color.fromARGB(255, 15, 23, 42),
                fontWeight: FontWeight.w600)),
        SizedBox(height: size.height * 0.01),
      ],
    );
  }

  // for taking pictures
  Future<void> _handleCameraPhoto() async {
    Navigator.of(context).pop();
    if (await Permission.camera.request() != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission denied')),
      );
      return;
    }
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (photo == null) return;
      final ext = '.jpg';
      final ref =
          FirebaseStorage.instance.ref().child('chatMedia/${Uuid().v4()}$ext');
      final upload = await ref.putFile(File(photo.path));
      final url = await upload.ref.getDownloadURL();
      await _chatCubit.sendMessage(
        content: url,
        receiverId: widget.receiverId,
        type: MessageType.image,
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Camera error: $e')));
    }
  }

  // for taking videos
  Future<void> _handleCameraVideo() async {}

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
      case MessageType.deleted:
        return '${prefix}Deleted message';
      case MessageType.text:
      default:
        return prefix + message.content;
    }
  }
}

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
      case MessageType.deleted:
        return '${prefix}Deleted message';
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
    final RenderBox renderBox = _key.currentContext!.findRenderObject() as RenderBox;
    final Size bubbleSize = renderBox.size;
    final Offset bubblePosition = renderBox.localToGlobal(Offset.zero);

    // Calculate position for reactions overlay
    final double screenWidth = MediaQuery.of(context).size.width;
    final double reactionsListWidth = size.width * 0.60;
    final double bubbleCenterX = bubblePosition.dx + bubbleSize.width / 2;
    final double x = (bubbleCenterX - reactionsListWidth / 2)
        .clamp(0.0, screenWidth - reactionsListWidth);
    final double y = bubblePosition.dy - 45;

    late final OverlayEntry overlay;
    
    void removeOverlay() {
      if (overlay.mounted) {
        overlay.remove();
      }
    }

    // Define the overlay
    overlay = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          // Transparent full-screen GestureDetector to handle taps outside
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => removeOverlay(),
            ),
          ),
          // Reactions menu
          Positioned(
            left: x,
            top: y,
            width: reactionsListWidth,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      offset: Offset(0.0, 0.0),
                      blurRadius: 8,
                      color: Color.fromARGB(150, 0, 0, 0),
                    ),
                  ],
                ),
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: reactions.asMap().entries.map((entry) {
                    final emoji = entry.value;
                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * -20),
                            child: GestureDetector(
                              onTap: () {
                                chatCubit.addReaction(
                                  messageId: message.id,
                                  emoji: emoji,
                                );
                                removeOverlay();
                              },
                              child: Text(
                                emoji,
                                style: TextStyle(
                                  fontSize: size.height * 0.025,
                                ),
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

    // Show both reactions overlay and options bottom sheet
    Overlay.of(context).insert(overlay);

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

    // Preload the audio to get its duration
    _loadAudioDuration();
  }

  Future<void> _loadAudioDuration() async {
    try {
      await _player.setSource(UrlSource(widget.url));
      // Wait a moment for the player to process the source
      await Future.delayed(const Duration(milliseconds: 100));
      final duration = await _player.getDuration();
      if (duration != null) {
        setState(() {
          _total = duration;
        });
      }
      await _player.stop();
    } catch (e) {
      // Handle error if needed
    }
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
    final iconColor = Theme.of(context).primaryColor;
    final progressColor = Theme.of(context).primaryColor;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          IconButton(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            iconSize: 28,
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
          const SizedBox(width: 8),
          // Start time
          Text(
            _format(_position),
            style: TextStyle(
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          // Waveform (static bars for now)
          Expanded(
            child: Container(
              height: 32,
              alignment: Alignment.center,
              child: CustomPaint(
                painter: _WaveformProgressPainter(
                  progress: _total.inMilliseconds == 0
                      ? 0
                      : _position.inMilliseconds / _total.inMilliseconds,
                  playedColor: Theme.of(context).primaryColor,
                  unplayedColor: Colors.grey[300]!,
                ),
                size: const Size(double.infinity, 32),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // End time
          Text(
            _format(_total),
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB2DFDB)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Draw static bars (you can randomize or use a fixed pattern)
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

class _WaveformProgressPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color playedColor;
  final Color unplayedColor;

  _WaveformProgressPainter({
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = 20;
    final barWidth = size.width / (barCount * 1.5);
    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth * 1.5 + barWidth / 2;
      final barHeight = size.height * (0.3 + 0.7 * (i % 2 == 0 ? 0.7 : 0.4));
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      final barProgress = (i + 1) / barCount;
      final color = barProgress <= progress ? playedColor : unplayedColor;

      final paint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
