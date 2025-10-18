import 'package:flutter_chatapp/services/chat_database.dart';
import 'package:flutter_chatapp/src/domain/entities/message.dart';
import 'package:flutter_chatapp/src/domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatDatabase _db;
  ChatRepositoryImpl({ChatDatabase? database})
    : _db = database ?? ChatDatabase();

  @override
  Future<int> saveConversation(List<MessageEntity> messages) async {
    final maps = messages.map((m) => m.toMap()).toList();
    return _db.saveConversation(maps);
  }

  @override
  Future<void> deleteConversation(int id) async {
    await _db.deleteConversation(id);
  }

  @override
  Future<List<Map<String, dynamic>>> getConversations() async {
    return _db.getConversations();
  }

  @override
  Future<void> updateConversation(int id, List<MessageEntity> messages) async {
    final maps = messages.map((m) => m.toMap()).toList();
    await _db.updateConversation(id, maps);
  }

  @override
  Future<void> updateConversationName(int id, String newName) async {
    await _db.updateConversationName(id, newName);
  }
}
