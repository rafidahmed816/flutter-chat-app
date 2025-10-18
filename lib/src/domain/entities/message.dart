class MessageEntity {
  final String role;
  final String content;

  const MessageEntity({required this.role, required this.content});

  Map<String, dynamic> toMap() => {'role': role, 'content': content};

  factory MessageEntity.fromMap(Map<String, dynamic> m) =>
      MessageEntity(role: m['role'] as String, content: m['content'] as String);
}
