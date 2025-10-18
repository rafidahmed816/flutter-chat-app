import 'package:flutter_chatapp/src/data/chat_repository_impl.dart';
import 'package:flutter_chatapp/src/domain/repositories/chat_repository.dart';
import 'package:flutter_chatapp/src/presentation/chat_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Repository provider
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepositoryImpl();
});

// Chat controller provider (requires baseUrl at runtime; expose a family)
final chatControllerProvider = Provider.family<ChatController, String>((
  ref,
  baseUrl,
) {
  final repo = ref.read(chatRepositoryProvider);
  return ChatController(repository: repo, baseUrl: baseUrl);
});

// Conversations state notifier - stores list of conversation maps as returned by repository
class StoredConversationsNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  StoredConversationsNotifier(this._controller) : super(const []);

  final ChatController _controller;

  // Load from repository
  Future<void> load() async {
    final list = await _controller.loadConversations();
    state = List<Map<String, dynamic>>.from(list);
  }

  // Upsert a draft entry (-1 id) or update its preview name/messages
  void upsertDraft({
    required String name,
    required List<Map<String, dynamic>> messages,
  }) {
    final idx = state.indexWhere((e) => e['id'] == -1);
    if (idx == -1) {
      state = [
        {
          'id': -1,
          'name': name,
          'messages': messages,
          'timestamp': DateTime.now().toIso8601String(),
        },
        ...state,
      ];
    } else {
      final updated = List<Map<String, dynamic>>.from(state);
      updated[idx] = {
        ...updated[idx],
        'name': name,
        'messages': messages,
        'timestamp': DateTime.now().toIso8601String(),
      };
      state = updated;
    }
  }

  // Replace the draft placeholder id with a real id after saving
  void commitDraftToId(int newId) {
    final idx = state.indexWhere((e) => e['id'] == -1);
    if (idx != -1) {
      final updated = List<Map<String, dynamic>>.from(state);
      updated[idx] = {...updated[idx], 'id': newId};
      state = updated;
    }
  }

  // Remove draft (-1) completely
  void clearDraft() {
    state = state.where((e) => e['id'] != -1).toList();
  }

  // Update conversation name locally and persist
  Future<void> updateName(int id, String newName) async {
    await _controller.updateConversationName(id, newName);
    final idx = state.indexWhere((e) => e['id'] == id);
    if (idx != -1) {
      final updated = List<Map<String, dynamic>>.from(state);
      updated[idx] = {...updated[idx], 'name': newName};
      state = updated;
    }
  }

  Future<void> delete(int id) async {
    await _controller.deleteConversation(id);
    state = state.where((e) => e['id'] != id).toList();
  }
}

// Expose conversations provider as a family keyed by baseUrl (uses same controller)
final storedConversationsProvider =
    StateNotifierProvider.family<
      StoredConversationsNotifier,
      List<Map<String, dynamic>>,
      String
    >((ref, baseUrl) {
      final controller = ref.read(chatControllerProvider(baseUrl));
      return StoredConversationsNotifier(controller);
    });
