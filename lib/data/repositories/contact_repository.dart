import 'package:firebase_auth/firebase_auth.dart';
import 'package:youtube_messenger_app/data/models/user_model.dart';
import 'package:youtube_messenger_app/data/services/base_repository.dart';

class ContactRepository extends BaseRepository {
  String get currentUserId => FirebaseAuth.instance.currentUser!.uid;

  Future<List<Map<String, dynamic>>> getRegisteredContacts() async {
    try {
      final snapshot = await firestore.collection('users').get();
      return snapshot.docs
          .map((doc) {
            final user = UserModel.fromFirestore(doc);
            if (user.uid == currentUserId) return null;
            return {
              'id': user.uid,
              'name': user.username ?? user.phoneNumber,
              'phoneNumber': user.phoneNumber,
            };
          })
          .where((e) => e != null)
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      print('Error fetching users: $e');
      return [];
    }
  }
}