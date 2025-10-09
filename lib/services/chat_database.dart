import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

class ChatDatabase {
  static final ChatDatabase _singleton = ChatDatabase._internal();
  factory ChatDatabase() => _singleton;
  ChatDatabase._internal();

  Database? _db;
  final _store = intMapStoreFactory.store('chats');

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/chat_history.db';
    _db = await databaseFactoryIo.openDatabase(dbPath);
    return _db!;
  }

  Future<int> saveConversation(List<Map<String, dynamic>> messages) async {
    final db = await database;
    return await _store.add(db, {
      'timestamp': DateTime.now().toIso8601String(),
      'messages': messages,
    });
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final db = await database;
    final snapshots = await _store.find(
      db,
      finder: Finder(sortOrders: [SortOrder('timestamp', false)]),
    );
    return snapshots
        .map((snap) => {'id': snap.key, ...snap.value as Map<String, dynamic>})
        .toList();
  }

  Future<void> updateConversation(
    int id,
    List<Map<String, dynamic>> messages,
  ) async {
    final db = await database;
    await _store.record(id).update(db, {
      'timestamp': DateTime.now().toIso8601String(),
      'messages': messages,
    });
  }

  Future<void> deleteConversation(int id) async {
    final db = await database;
    await _store.record(id).delete(db);
  }

  Future<void> updateConversationName(int id, String newName) async {
    final db = await database;
    final record = _store.record(id);
    final existing = await record.get(db);
    if (existing != null) {
      await record.update(db, {...existing, 'name': newName});
    }
  }
}
