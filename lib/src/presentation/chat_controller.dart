import 'package:flutter_chatapp/src/domain/entities/message.dart';
import 'package:flutter_chatapp/src/domain/repositories/chat_repository.dart';
import 'package:ollama/ollama.dart';

class ChatController {
  final ChatRepository repository;
  final String baseUrl;
  late final Ollama ollama;

  ChatController({required this.repository, required this.baseUrl}) {
    ollama = Ollama(baseUrl: Uri.parse(baseUrl));
  }

  Future<List<Map<String, dynamic>>> loadConversations() async {
    return repository.getConversations();
  }

  Future<int> saveConversation(List<MessageEntity> messages) async {
    return repository.saveConversation(messages);
  }

  Future<void> updateConversation(int id, List<MessageEntity> messages) async {
    return repository.updateConversation(id, messages);
  }

  Future<void> deleteConversation(int id) async {
    return repository.deleteConversation(id);
  }

  Future<void> updateConversationName(int id, String newName) async {
    return repository.updateConversationName(id, newName);
  }

  Stream<dynamic> chatStream(
    List<ChatMessage> messages, {
    String model = 'gemma3:4b',
    ModelOptions? options,
  }) {
    return ollama.chat(messages, model: model, options: options);
  }
}
