import 'package:flutter/material.dart';
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

  @override
  void initState() {
    _contactRepository = getIt<ContactRepository>();
    _chatRepository = getIt<ChatRepository>();
    _currentUserId = getIt<AuthRepository>().currentUser?.uid ?? "";

    super.initState();
  }

  void _showContactsList(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (_) => Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('Users', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _contactRepository.getRegisteredContacts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final users = snapshot.data!;
                if (users.isEmpty) return const Center(child: Text("No users found"));

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, i) {
                    final user = users[i];
                    return ListTile(
                      leading: user['photoUrl'] != null
                          ? CircleAvatar(backgroundImage: NetworkImage(user['photoUrl']))
                          : CircleAvatar(child: Text(user['name'][0].toUpperCase())),
                      title: Text(user['name']),
                      subtitle: Text(user['phoneNumber']),
                      onTap: () {
                        getIt<AppRouter>().push(
                          ChatMessageScreen(
                            receiverId: user['id'],
                            receiverName: user['name'],
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
    ),
  );
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
            child: const Icon(
              Icons.logout,
            ),
          )
        ],
      ),
      body: StreamBuilder(
          stream: _chatRepository.getChatRooms(_currentUserId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              print(snapshot.error);
              return Center(
                child: Text("error:${snapshot.error}"),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final chats = snapshot.data!;
            if (chats.isEmpty) {
              return const Center(
                child: Text("No recent chats"),
              );
            }
            return ListView.builder(
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  return ChatListTile(
                    chat: chat,
                    currentUserId: _currentUserId,
                    onTap: () {
                      final otherUserId = chat.participants
                          .firstWhere((id) => id != _currentUserId);
                      print("home screen current user id $_currentUserId");
                      final outherUserName =
                          chat.participantsName?[otherUserId] ?? "Unknown";
                      getIt<AppRouter>().push(ChatMessageScreen(
                          receiverId: otherUserId,
                          receiverName: outherUserName));
                    },
                  );
                });
          }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showContactsList(context),
        child: const Icon(
          Icons.chat,
          color: Colors.white,
        ),
      ),
    );
  }
}
