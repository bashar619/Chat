// lib/presentaion/chat/chat_message_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';
import 'package:youtube_messenger_app/data/services/service_locator.dart';
import 'package:youtube_messenger_app/logic/cubits/chat/chat_cubit.dart';
import 'package:youtube_messenger_app/logic/cubits/chat/chat_state.dart';
import 'package:youtube_messenger_app/presentation/chat/Message_bubble.dart';
import 'package:youtube_messenger_app/presentation/chat/media_handler.dart';
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
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isRecordingVideo = false;
  String? _videoFilePath;
  bool _hasBadWords = false;

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
        const SnackBar(
            content:
                Text('Microphone permission is required for voice messages')),
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
          final ref = FirebaseStorage.instance
              .ref()
              .child('voiceMessages/$fileName.m4a');
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

  Future<void> _onTextChanged() async {
    final current = messageController.text;
    final isNowComposing = current.isNotEmpty;

    // Immediately update whether we're composing at all
    if (isNowComposing != _isComposing) {
      setState(() {
        _isComposing = isNowComposing;
      });
    }
    // 4) Your existing “typing…” signal
    if (isNowComposing) {
      _chatCubit.startTyping();
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
  Future<void> _handleCameraVideo() async {
    // Request permissions
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (cameraStatus != PermissionStatus.granted ||
        micStatus != PermissionStatus.granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera & microphone permissions required'),
        ),
      );
      return;
    }

    // Initialize the camera controller as before...
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    await _cameraController?.dispose();
    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Camera init failed: $e')));
      return;
    }

    // Push full‑screen recorder page and wait for the recorded file path
    final videoPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => VideoRecorderPage(controller: controller),
      ),
    );
    // controller will be disposed by the recorder page

    if (videoPath != null) {
      await _processVideoFile(videoPath);
    }
  }

  Future<void> _processVideoFile(String path) async {
    bool uploadCancelled = false;

    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in!')),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async {
          uploadCancelled = true;
          return true;
        },
        child: AlertDialog(
          title: const Text('Processing Video'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  uploadCancelled = true;
                  Navigator.pop(context);
                },
                child: const Text('Cancel Upload'),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() < 1024) {
        throw Exception('Invalid video file');
      }

      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final ref = FirebaseStorage.instance.ref().child('chatVideos/$fileName');
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(
          contentType: 'video/mp4',
          customMetadata: {
            'uploaderId': FirebaseAuth.instance.currentUser!.uid,
          },
        ),
      );

      final snapshot = await uploadTask.whenComplete(() {});

      if (uploadCancelled || !mounted) {
        await snapshot.ref.delete();
        return;
      }

      final downloadUrl = await snapshot.ref.getDownloadURL();

      await _chatCubit.sendMessage(
        content: downloadUrl,
        receiverId: widget.receiverId,
        type: MessageType.video,
      );
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child:
                                  const Icon(Icons.reply, color: Colors.grey),
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
                                  color: _isRecording
                                      ? Colors.red
                                      : Theme.of(context).primaryColor,
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
