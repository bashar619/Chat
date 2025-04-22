// firebase-functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendChatNotification = functions.firestore
  .document('chatRooms/{chatRoomId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    
    // Don't send notification if sender == receiver
    if (message.senderId === message.receiverId) return null;

    // Get receiver's FCM tokens
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(message.receiverId)
      .get();

    const tokens = userDoc.data()?.fcmTokens || [];
    if (tokens.length === 0) return null;

    // Get sender's name
    const senderDoc = await admin.firestore()
      .collection('users')
      .doc(message.senderId)
      .get();
    
    const senderName = senderDoc.data()?.fullName || 'Someone';

    // Construct notification
    const payload = {
      notification: {
        title: senderName,
        body: message.type === 'text' ? message.content : 'New media message',
        sound: 'default'
      },
      data: {
        chatRoomId: message.chatRoomId,
        senderId: message.senderId
      },
      tokens: tokens
    };

    // Send notification
    return admin.messaging().sendMulticast(payload);
  });