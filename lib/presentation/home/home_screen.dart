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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ContactRepository _contactRepository;
  late final ChatRepository _chatRepository;
  late final String _currentUserId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _contactRepository = getIt<ContactRepository>();
    _chatRepository = getIt<ChatRepository>();
    _currentUserId = getIt<AuthRepository>().currentUser?.uid ?? "";
  }

  void _showContactsList(BuildContext context) { /* unchanged */ }

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
          // ─── Search Bar ───────────────────────
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search chats',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
              ),
              onChanged: (v) => setState(() {
                _search = v.trim().toLowerCase();
              }),
            ),
          ),

          // ─── Chat Rooms List ──────────────────
          Expanded(
            child: StreamBuilder<List<ChatRoomModel>>(
              stream: _chatRepository.getChatRooms(_currentUserId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allChats = snapshot.data!;
                // filter by other user's name
                final filtered = allChats.where((chat) {
                  final otherId = chat.participants
                      .firstWhere((id) => id != _currentUserId);
                  final otherName =
                      (chat.participantsName?[otherId] ?? '')
                          .toLowerCase();
                  return otherName.contains(_search);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _search.isEmpty
                          ? 'No recent chats'
                          : 'No chats match "$_search"',
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final chat = filtered[index];
                    final otherId = chat.participants
                        .firstWhere((id) => id != _currentUserId);
                    final otherName =
                        chat.participantsName?[otherId] ?? 'Unknown';

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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showContactsList(context),
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }
}