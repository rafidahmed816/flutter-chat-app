import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chatapp/src/domain/entities/message.dart' as domain;
import 'package:flutter_chatapp/src/presentation/chat_controller.dart';
import 'package:flutter_chatapp/src/presentation/providers.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ollama/ollama.dart';

class ChatScreen extends ConsumerStatefulWidget {
  static const routeName = '/chat';
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final ChatController _controllerImpl;

  final List<_Message> _history = [
    const _Message(role: 'system', content: 'You are a helpful AI assistant.'),
  ];

  // Sidebar animation
  List<bool> _visibleSidebarItems = [];

  // Message animation
  List<bool> _visibleMessages = [];
  bool _animatingHistory = false;

  bool _isStreaming = false;
  String _streamBuffer = '';
  final bool _hideThinking = true;

  int? _currentConversationId;
  int? _editingConversationId;

  String get _defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:11434';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:11434';
      default:
        return 'http://127.0.0.1:11434';
    }
  }

  @override
  void initState() {
    super.initState();
    _controllerImpl = ref.read(chatControllerProvider(_defaultBaseUrl));
    _loadStoredConversations();
  }

  @override
  void dispose() {
    _controller.dispose();
    _editController.dispose();
    _scrollController.dispose();
    _saveCurrentConversation();
    super.dispose();
  }

  Future<void> _loadStoredConversations() async {
    await ref
        .read(storedConversationsProvider(_defaultBaseUrl).notifier)
        .load();
    if (!mounted) return;
    final conversations = ref.read(
      storedConversationsProvider(_defaultBaseUrl),
    );
    setState(() {
      _visibleSidebarItems = List.generate(conversations.length, (_) => false);
    });
    for (int i = 0; i < conversations.length; i++) {
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (!mounted) return;
        setState(() {
          if (i < _visibleSidebarItems.length) _visibleSidebarItems[i] = true;
        });
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isStreaming) return;

    final messages = [
      for (final m in _history)
        if (m.content.trim().isNotEmpty)
          ChatMessage(role: m.role, content: m.content),
      ChatMessage(role: 'user', content: text),
    ];

    setState(() {
      _history.add(_Message(role: 'user', content: text));
      _controller.clear();
      _isStreaming = true;
      _history.add(const _Message(role: 'assistant', content: ''));
      _streamBuffer = '';
    });

    // Update draft in sidebar immediately
    _updateDraftSidebar(name: text);

    try {
      final stream = _controllerImpl.chatStream(
        messages,
        model: 'gemma3:4b',
        options: ModelOptions(
          temperature: 0.7,
          topP: 0.9,
          numPredict: 1024,
          repeatPenalty: 1.05,
        ),
      );

      await for (final chunk in stream) {
        final piece = (chunk as dynamic).message?.content ?? '';
        if (piece.isEmpty) continue;

        _streamBuffer += piece;

        if (!_hideThinking) {
          final visible = _filterThinking(_streamBuffer);
          setState(() {
            final lastIndex = _history.lastIndexWhere(
              (m) => m.role == 'assistant',
            );
            if (lastIndex != -1) {
              _history[lastIndex] = _history[lastIndex].copyWith(
                content: visible.trim(),
              );
            }
          });
          _scrollToBottom();
        }

        // Update draft while streaming
        _updateDraftSidebar(name: text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _history.add(_Message(role: 'assistant', content: 'Error: $e'));
      });
    } finally {
      if (!mounted) return;

      if (_hideThinking && _streamBuffer.isNotEmpty) {
        final finalResponse = _filterThinking(_streamBuffer).trim();
        setState(() {
          final lastIndex = _history.lastIndexWhere(
            (m) => m.role == 'assistant',
          );
          if (lastIndex != -1) {
            _history[lastIndex] = _history[lastIndex].copyWith(
              content: finalResponse,
            );
          }
        });
      }

      setState(() {
        _isStreaming = false;
      });

      await _saveCurrentConversation();
      await _loadStoredConversations();
    }
  }

  void _updateDraftSidebar({required String name}) {
    ref
        .read(storedConversationsProvider(_defaultBaseUrl).notifier)
        .upsertDraft(
          name: name,
          messages: _history
              .where((m) => m.role != 'system')
              .map((m) => {'role': m.role, 'content': m.content})
              .toList(),
        );
  }

  Future<void> _saveCurrentConversation() async {
    final messages = _history
        .where((m) => m.role != 'system')
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    if (messages.isNotEmpty &&
        messages.any((m) => m['content']?.trim().isNotEmpty == true)) {
      if (_currentConversationId != null) {
        await _controllerImpl.updateConversation(
          _currentConversationId!,
          messages.map((m) => domain.MessageEntity.fromMap(m)).toList(),
        );
      } else {
        _currentConversationId = await _controllerImpl.saveConversation(
          messages.map((m) => domain.MessageEntity.fromMap(m)).toList(),
        );
        ref
            .read(storedConversationsProvider(_defaultBaseUrl).notifier)
            .commitDraftToId(_currentConversationId!);
      }
    }
  }

  void _loadConversationFromDB(Map<String, dynamic> convo) {
    final messages = (convo['messages'] as List)
        .map((m) => _Message(role: m['role'], content: m['content']))
        .toList();

    setState(() {
      _currentConversationId = convo['id'] as int?;
      _animatingHistory = true;

      _history
        ..clear()
        ..add(
          const _Message(
            role: 'system',
            content: 'You are a helpful AI assistant.',
          ),
        )
        ..addAll(messages);

      _visibleMessages = List.generate(messages.length, (_) => false);
    });

    for (int i = 0; i < messages.length; i++) {
      final delay = i < 5 ? (i * 150) : (750 + ((i - 5) * 100));
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        setState(() {
          if (i < _visibleMessages.length) _visibleMessages[i] = true;
          if (i == messages.length - 1) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (!mounted) return;
              setState(() {
                _animatingHistory = false;
              });
            });
          }
        });
        _scrollToBottom();
      });
    }
  }

  Future<void> _deleteConversation(int conversationId) async {
    await _controllerImpl.deleteConversation(conversationId);
    await _loadStoredConversations();
  }

  void _startEditingConversation(int conversationId, String currentName) {
    setState(() {
      _editingConversationId = conversationId;
      _editController.text = currentName;
    });
  }

  Future<void> _saveConversationName(int conversationId) async {
    final newName = _editController.text.trim();
    if (newName.isNotEmpty) {
      await _controllerImpl.updateConversationName(conversationId, newName);
      await _loadStoredConversations();
    }
    setState(() {
      _editingConversationId = null;
      _editController.clear();
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingConversationId = null;
      _editController.clear();
    });
  }

  void _showDeleteConfirmation(
    BuildContext context,
    int conversationId,
    String displayName,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Conversation'),
          content: Text('Are you sure you want to delete "$displayName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteConversation(conversationId);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuad,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat App'),backgroundColor: const Color.fromARGB(255, 93, 186, 220),),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.add_comment_outlined),
                title: const Text('New Chat'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _currentConversationId = null;
                    _history
                      ..clear()
                      ..add(
                        const _Message(
                          role: 'system',
                          content: 'You are a helpful AI assistant.',
                        ),
                      );
                  });
                  ref
                      .read(
                        storedConversationsProvider(_defaultBaseUrl).notifier,
                      )
                      .clearDraft();
                },
              ),
              const Divider(),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final conversations = ref.watch(
                      storedConversationsProvider(_defaultBaseUrl),
                    );
                    return ListView.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final convo = conversations[index];
                        final conversationId = convo['id'] as int? ?? index;
                        final firstMsg = (convo['messages'] as List).isNotEmpty
                            ? convo['messages'][0]['content']
                            : 'Conversation';
                        final displayName =
                            convo['name'] as String? ?? firstMsg;

                        final isEditing =
                            _editingConversationId == conversationId;
                        final isVisible = index < _visibleSidebarItems.length
                            ? _visibleSidebarItems[index]
                            : true;

                        Widget listTileWidget = ListTile(
                          title: isEditing
                              ? TextField(
                                  controller: _editController,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter conversation name',
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) =>
                                      _saveConversationName(conversationId),
                                )
                              : Text(
                                  displayName.length > 40
                                      ? '${displayName.substring(0, 40)}...'
                                      : displayName,
                                ),
                          trailing: isEditing
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check,
                                        color: Colors.green,
                                      ),
                                      onPressed: () =>
                                          _saveConversationName(conversationId),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.cancel,
                                        color: Colors.red,
                                      ),
                                      onPressed: _cancelEditing,
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed: () =>
                                          _startEditingConversation(
                                            conversationId,
                                            displayName,
                                          ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      onPressed: () => _showDeleteConfirmation(
                                        context,
                                        conversationId,
                                        displayName,
                                      ),
                                    ),
                                  ],
                                ),
                          onTap: isEditing
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _loadConversationFromDB(convo);
                                },
                        );

                        return AnimatedOpacity(
                          opacity: isVisible ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          child: listTileWidget,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final m = _history[index];
                if (m.role == 'system') return const SizedBox.shrink();

                final isUser = m.role == 'user';
                final adjustedIndex = index - 1;
                final shouldAnimate =
                    _animatingHistory &&
                    adjustedIndex >= 0 &&
                    adjustedIndex < _visibleMessages.length;
                final isVisible =
                    !shouldAnimate ||
                    (shouldAnimate && _visibleMessages[adjustedIndex]);

                Widget messageWidget = Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 650),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: !isUser && m.content.isEmpty && _isStreaming
                      ? _buildThinkingAnimation()
                      : (isUser
                            ? SelectableText(
                                m.content,
                                style: const TextStyle(color: Colors.black),
                              )
                            : MarkdownBody(data: m.content, selectable: true)),
                );

                if (shouldAnimate) {
                  messageWidget = AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutQuad,
                    transform: Matrix4.translationValues(
                      isVisible ? 0 : (isUser ? 50 : -50),
                      0,
                      0,
                    ),
                    child: AnimatedOpacity(
                      opacity: isVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutQuad,
                      child: messageWidget,
                    ),
                  );
                }

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: messageWidget,
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Ask anything...',
                      prefixIcon: const Icon(Icons.chat_bubble_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      ref
                          .read(
                            storedConversationsProvider(
                              _defaultBaseUrl,
                            ).notifier,
                          )
                          .upsertDraft(
                            name: value,
                            messages: [
                              ..._history
                                  .where((m) => m.role != 'system')
                                  .map(
                                    (m) => {
                                      'role': m.role,
                                      'content': m.content,
                                    },
                                  ),
                              if (value.trim().isNotEmpty)
                                {'role': 'user', 'content': value},
                            ],
                          );
                    },
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _isStreaming ? null : _sendMessage,
                  icon: _isStreaming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message {
  final String role;
  final String content;
  const _Message({required this.role, required this.content});
  _Message copyWith({String? role, String? content}) =>
      _Message(role: role ?? this.role, content: content ?? this.content);
}

Widget _buildThinkingAnimation() {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Thinking', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(width: 36, child: _ThinkingDots()),
    ],
  );
}

class _ThinkingDots extends StatefulWidget {
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _opacities = [0.3, 0.3, 0.3];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _controller.addListener(_updateDots);
  }

  void _updateDots() {
    final progress = _controller.value * 3;
    setState(() {
      for (int i = 0; i < 3; i++) {
        final dotProgress = (progress - i).clamp(0.0, 1.0);
        _opacities[i] = 0.3 + (dotProgress * 0.7);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(3, (i) => _buildDot(_opacities[i])),
    );
  }

  Widget _buildDot(double opacity) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

String _filterThinking(String raw) {
  var s = raw;
  s = s.replaceAll(
    RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false),
    '',
  );
  s = s.replaceAll(RegExp(r'```thinking[\s\S]*?```', caseSensitive: false), '');
  s = s.replaceAll(
    RegExp(r'\[think\][\s\S]*?\[\/think\]', caseSensitive: false),
    '',
  );
  s = s.replaceAll(
    RegExp(
      r'^\s*(Reasoning|Thoughts|Chain[- ]?of[- ]?Thought)\s*:\s*[\s\S]*?\n\s*\n',
      caseSensitive: false,
    ),
    '',
  );
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
