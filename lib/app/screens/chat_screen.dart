import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ollama/ollama.dart';

import '../../services/chat_database.dart';

class ChatScreen extends StatefulWidget {
  static const routeName = '/chat';
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final Ollama _ollama;

  final List<_Message> _history = [
    const _Message(
      role: 'system',
      content: '''
You are DeepSeek, a concise and highly intelligent AI assistant running locally.
- Always provide clear, accurate, and complete answers.
- Do NOT explain your reasoning or thought process unless explicitly asked.
- If asked to code, return clean, production-ready code.
- If unsure, say so clearly rather than guessing.
''',
    ),
  ];

  List<Map<String, dynamic>> _storedConversations = [];
  bool _isStreaming = false;
  String _streamBuffer = '';
  final bool _hideThinking = true;

  // For editing conversation names
  int? _editingConversationId;
  TextEditingController _editController = TextEditingController();

  // Track current conversation ID to avoid duplicates
  int? _currentConversationId;
  
  // Animation-related properties
  List<bool> _visibleMessages = [];
  bool _animatingHistory = false;

  @override
  void initState() {
    super.initState();
    _ollama = Ollama(baseUrl: Uri.parse(_defaultBaseUrl));
    _loadStoredConversations();
  }

  Future<void> _loadStoredConversations() async {
    final chats = await ChatDatabase().getConversations();
    if (!mounted) return;
    setState(() {
      _storedConversations = List<Map<String, dynamic>>.from(chats);
    });
  }

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
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    // Save current conversation when leaving the screen
    _saveCurrentConversation();
    super.dispose();
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

    try {
      final stream = _ollama.chat(
        messages,
        model: 'deepseek-r1:8b',
        options: ModelOptions(
          temperature: 0.7,
          topP: 0.9,
          numPredict: 1024,
          repeatPenalty: 1.05,
        ),
      );

      String _streamBufferRaw = '';

      await for (final chunk in stream) {
        final piece = chunk.message?.content ?? '';
        if (piece.isEmpty) continue;

        // Append raw piece to buffer
        _streamBuffer += piece;

        // Don't show partial text while thinking
        // Only update the UI after processing is complete or periodically
        if (!_hideThinking) {
          // Filter only the visible text (remove think tags cleanly)
          final visible = _filterThinking(_streamBufferRaw);

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
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _history.add(_Message(role: 'assistant', content: 'Error: $e'));
      });
    } finally {
      if (!mounted) return;

      // Apply final filtering on the entire response
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
      // Remove automatic saving after each message to prevent duplicates
      // await _saveCurrentConversation();
      // await _loadStoredConversations();
    }
  }

  Future<void> _saveCurrentConversation() async {
    final messages = _history
        .where((m) => m.role != 'system')
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    // Only save if there are actual user/assistant messages
    if (messages.isNotEmpty &&
        messages.any((m) => m['content']?.trim().isNotEmpty == true)) {
      if (_currentConversationId != null) {
        // Update existing conversation
        await ChatDatabase().updateConversation(
          _currentConversationId!,
          messages,
        );
      } else {
        // Create new conversation
        _currentConversationId = await ChatDatabase().saveConversation(
          messages,
        );
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
      
      // Reset the message list with just the system prompt
      _history
        ..clear()
        ..add(
          const _Message(
            role: 'system',
            content: '''
You are DeepSeek, a concise and highly intelligent AI assistant running locally.
''',
          ),
        );
      
      // Add all messages to history but keep them invisible
      _history.addAll(messages);
      
      // Initialize all messages as invisible
      _visibleMessages = List.generate(messages.length, (_) => false);
    });
    
    // Animate each message appearing one by one with a staggered effect
    for (int i = 0; i < messages.length; i++) {
      // Calculate a staggered delay - messages appear faster as they load
      int delay = i < 5 ? (i * 150) : (750 + ((i - 5) * 100));
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        setState(() {
          // Make the message visible
          if (i < _visibleMessages.length) {
            _visibleMessages[i] = true;
          }
          
          // Mark animation as complete when all messages are shown
          if (i == messages.length - 1) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (!mounted) return;
              setState(() {
                _animatingHistory = false;
              });
            });
          }
        });
        
        // Scroll to show the latest message
        _scrollToBottom();
      });
    }
  }

  void _newConversation() async {
    // Save current conversation before starting new one
    await _saveCurrentConversation();
    await _loadStoredConversations();

    setState(() {
      _currentConversationId = null; // Reset to create new conversation
      _history
        ..clear()
        ..add(
          const _Message(
            role: 'system',
            content: '''
You are DeepSeek, a concise and highly intelligent AI assistant running locally.
''',
          ),
        );
    });
  }

  Future<void> _deleteConversation(int conversationId) async {
    await ChatDatabase().deleteConversation(conversationId);
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
      await ChatDatabase().updateConversationName(conversationId, newName);
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
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.add_comment_outlined),
                title: const Text('New Chat'),
                onTap: () {
                  Navigator.pop(context);
                  _newConversation();
                },
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: _storedConversations.length,
                  itemBuilder: (context, index) {
                    final convo = _storedConversations[index];
                    final conversationId =
                        convo['id'] as int? ??
                        index; // Use actual ID if available
                    final firstMsg = (convo['messages'] as List).isNotEmpty
                        ? convo['messages'][0]['content']
                        : 'Conversation';
                    final displayName = convo['name'] as String? ?? firstMsg;

                    final isEditing = _editingConversationId == conversationId;

                    return ListTile(
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
                                  onPressed: () => _startEditingConversation(
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
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(title: const Text('DeepSeek Chat')),
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
                final adjustedIndex = index - 1; // Adjust for system message
                
                // Determine if this message should be animated
                final shouldAnimate = _animatingHistory && 
                                      adjustedIndex >= 0 && 
                                      adjustedIndex < _visibleMessages.length;
                
                // Get message visibility for animation
                final isVisible = !shouldAnimate || 
                                 (shouldAnimate && adjustedIndex < _visibleMessages.length && 
                                  _visibleMessages[adjustedIndex]);
                
                // Build the message widget
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
                      : SelectableText(
                          m.content,
                          style: TextStyle(
                            color: isUser ? Colors.black : Colors.black87,
                          ),
                        ),
                );
                
                // Apply combined slide and fade-in animation
                if (shouldAnimate) {
                  messageWidget = AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutQuad,
                    transform: Matrix4.translationValues(
                      0, 
                      isVisible ? 0 : (isUser ? 20 : -20), 
                      0
                    ),
                    child: AnimatedOpacity(
                      opacity: isVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutQuad,
                      child: messageWidget,
                    ),
                  );
                }
                
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
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
