// lib/presentation/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:youtube_messenger_app/data/models/chat_room_model.dart';
import 'package:youtube_messenger_app/data/repositories/auth_repository.dart';
import 'package:youtube_messenger_app/data/repositories/chat_repository.dart';
import 'package:youtube_messenger_app/data/repositories/contact_repository.dart';
import 'package:youtube_messenger_app/data/services/service_locator.dart';
import 'package:youtube_messenger_app/logic/cubits/auth/auth_cubit.dart';
import 'package:youtube_messenger_app/presentation/chat/chat_message_screen.dart';
import 'package:youtube_messenger_app/presentation/screens/auth/login_screen.dart';
import 'package:youtube_messenger_app/presentation/widgets/chat_list_tile.dart';
import 'package:youtube_messenger_app/router/app_router.dart';

enum ChatFilter { all, read, unread }
enum ChatSort   { newest, oldest, aToZ, zToA }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ContactRepository _contactRepository;
  late final ChatRepository    _chatRepository;
  late final String            _currentUserId;

  String      _search = '';
  ChatFilter  _filter = ChatFilter.all;
  ChatSort    _sort   = ChatSort.newest;

  @override
  void initState() {
    super.initState();
    _contactRepository = getIt<ContactRepository>();
    _chatRepository    = getIt<ChatRepository>();
    _currentUserId     = getIt<AuthRepository>().currentUser?.uid ?? "";
  }

  void _showContactsList(BuildContext context) { /* unchanged */ }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ChatFilter>(
              title: const Text('All messages'),
              value: ChatFilter.all,
              groupValue: _filter,
              onChanged: (v) {
                setState(() => _filter = v!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ChatFilter>(
              title: const Text('Already read messages'),
              value: ChatFilter.read,
              groupValue: _filter,
              onChanged: (v) {
                setState(() => _filter = v!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ChatFilter>(
              title: const Text('Unread messages'),
              value: ChatFilter.unread,
              groupValue: _filter,
              onChanged: (v) {
                setState(() => _filter = v!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ChatSort>(
              title: const Text('🆕 Newest'),
              value: ChatSort.newest,
              groupValue: _sort,
              onChanged: (v) {
                setState(() => _sort = v!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ChatSort>(
              title: const Text('📜 Oldest'),
              value: ChatSort.oldest,
              groupValue: _sort,
              onChanged: (v) {
                setState(() => _sort = v!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ChatSort>(
              title: const Text('A → Z'),
              value: ChatSort.aToZ,
              groupValue: _sort,
              onChanged: (v) {
                setState(() => _sort = v!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ChatSort>(
              title: const Text('Z → A'),
              value: ChatSort.zToA,
              groupValue: _sort,
              onChanged: (v) {
                setState(() => _sort = v!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _passesReadFilter(ChatRoomModel chat) {
  // If the current user sent the last message, treat the room as read.
  if (chat.lastMessageSenderId == _currentUserId) return true;

  final lastMsgTs = chat.lastMessageTime?.toDate();
  final lastReadTs = chat.lastReadTime?[_currentUserId]?.toDate();
  
  // The room is unread if the last message exists and its timestamp is later
  // than the last read timestamp (or if no last read timestamp is stored).
  final isUnread =
      lastMsgTs != null && (lastReadTs == null || lastMsgTs.isAfter(lastReadTs));

  switch (_filter) {
    case ChatFilter.all:
      return true;
    case ChatFilter.read:
      return !isUnread;
    case ChatFilter.unread:
      return isUnread;
  }
}


  String _otherName(ChatRoomModel chat) {
    final otherId = chat.participants.firstWhere((id) => id != _currentUserId);
    return chat.participantsName?[otherId] ?? '';
  }

  List<ChatRoomModel> _applySort(List<ChatRoomModel> list) {
    final copy = List<ChatRoomModel>.from(list);
    copy.sort((a, b) {
      switch (_sort) {
        case ChatSort.newest:
          final aTs = a.lastMessageTime?.toDate() ?? DateTime(0);
          final bTs = b.lastMessageTime?.toDate() ?? DateTime(0);
          return bTs.compareTo(aTs);
        case ChatSort.oldest:
          final aTs = a.lastMessageTime?.toDate() ?? DateTime(0);
          final bTs = b.lastMessageTime?.toDate() ?? DateTime(0);
          return aTs.compareTo(bTs);
        case ChatSort.aToZ:
          return _otherName(a).toLowerCase().compareTo(_otherName(b).toLowerCase());
        case ChatSort.zToA:
          return _otherName(b).toLowerCase().compareTo(_otherName(a).toLowerCase());
      }
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chats"),
        actions: [
          InkWell(
            onTap: () async {
              await getIt<AuthCubit>().signOut();
              getIt<AppRouter>().pushAndRemoveUntil(const LoginScreen());
            },
            child: const Icon(Icons.logout),
          )
        ],
      ),
      body: Column(
        children: [
          //search Bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search chats',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),

          //chat Rooms List
          Expanded(
            child: StreamBuilder<List<ChatRoomModel>>(
              stream: _chatRepository.getChatRooms(_currentUserId),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                // filter by name & read/unread
                final filtered = snap.data!
                    .where((c) => _otherName(c).toLowerCase().contains(_search))
                    .where(_passesReadFilter)
                    .toList();

                // then sort
                final sorted = _applySort(filtered);

                if (sorted.isEmpty) {
                  return Center(
                    child: Text(
                      _search.isEmpty
                          ? 'No recent chats'
                          : 'No chats match "$_search"',
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, i) {
                    final chat    = sorted[i];
                    final otherId = chat.participants.firstWhere((id) => id != _currentUserId);
                    final otherName = chat.participantsName?[otherId] ?? 'Unknown';

                    return ChatListTile(
                      chat: chat,
                      currentUserId: _currentUserId,
                      onTap: () {
                        getIt<AppRouter>().push(
                          ChatMessageScreen(
                            receiverId: otherId,
                            receiverName: otherName,
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      //fitler and sort buttons
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _showFilterOptions,
              icon: const Icon(Icons.filter_list),
              label: const Text('Filter'),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _showSortOptions,
              icon: const Icon(Icons.sort),
              label: const Text('Sort'),
            ),
          ],
        ),
      ),

      //FAB
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showContactsList(context),
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }
}