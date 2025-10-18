import '../entities/message.dart';

abstract class ChatRepository {
  Future<int> saveConversation(List<MessageEntity> messages);
  Future<List<Map<String, dynamic>>> getConversations();
  Future<void> updateConversation(int id, List<MessageEntity> messages);
  Future<void> deleteConversation(int id);
  Future<void> updateConversationName(int id, String newName);
}
