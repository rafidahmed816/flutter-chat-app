import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chatapp/app/screens/chat_screen.dart';

class OnboardingScreen extends StatefulWidget {
  static const routeName = '/onboarding';
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final List<String> _images = [
    'assets/images/onb_1.jpg',
    'assets/images/onb_2.jpg',
    'assets/images/chat.png',
  ];

  final List<String> _titles = [
    'Welcome to Ollama Chat',
    'Local AI Conversations',
    'Start Chatting Now',
  ];

  final List<String> _descriptions = [
    'Experience intelligent conversations powered by local AI',
    'Your privacy matters - all conversations stay on your device',
    'Ask questions, get answers, and explore ideas with DeepSeek',
  ];

  int _currentIndex = 0;
  late List<AnimationController> _controllers;
  late List<Animation<double>> _opacityAnimations;
  late AnimationController _exitController;
  late Animation<double> _exitOpacityAnimation;

  // Text animation
  late AnimationController _textController;
  int _visibleWordCount = 0;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(
      3,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 800),
        vsync: this,
      ),
    );

    _exitController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _opacityAnimations = _controllers
        .map(
          (c) => Tween<double>(
            begin: 0,
            end: 1,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();

    // Simple fade out animation for transitions
    _exitOpacityAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInOut),
    );

    _textController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    for (int i = 0; i < _controllers.length; i++) {
      if (!mounted) return;

      // For screens after the first one, fade out the current screen first
      if (i > 0) {
        // Fade out current screen
        await _exitController.forward(from: 0);
        await Future.delayed(
          const Duration(milliseconds: 300),
        ); // Short pause after fade out
      }

      // Set the new screen index and fade it in
      setState(() => _currentIndex = i);
      await _controllers[i].forward(from: 0);

      // Start text animation after image appears
      _visibleWordCount = 0;
      _textController.reset();
      _startTextAnimation(_titles[i] + ' ' + _descriptions[i]);

      // Wait a bit before going to the next screen
      await Future.delayed(const Duration(milliseconds: 1800));
    }

    // Short pause before navigating to the main app
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      Navigator.of(context).pushReplacementNamed(ChatScreen.routeName);
    }
  }

  void _startTextAnimation(String text) {
    final words = text.split(' ');
    _visibleWordCount = 0;

    // Slightly faster text animation (100ms per word)
    for (int i = 0; i <= words.length; i++) {
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) {
          setState(() => _visibleWordCount = i);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _exitController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(child: _buildOnboardingItem(_currentIndex)),
        ),
      ),
    );
  }

  Widget _buildOnboardingItem(int index) {
    Widget animatedImage;

    // Simple fade in animation for all screens
    animatedImage = FadeTransition(
      opacity: _opacityAnimations[index],
      child: _buildImageCard(index),
    );

    if (_exitController.isAnimating || _exitController.value > 0) {
      animatedImage = FadeTransition(
        opacity: _exitOpacityAnimation,
        child: animatedImage,
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        animatedImage,
        const SizedBox(height: 40),
        AnimatedOpacity(
          opacity: _controllers[index].value,
          duration: const Duration(milliseconds: 500),
          child: _buildAnimatedText(_titles[index], _descriptions[index]),
        ),
      ],
    );
  }

  Widget _buildAnimatedText(String title, String description) {
    final words = (title + ' ' + description).split(' ');

    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: _buildTextSpans(title, words, 0),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 16),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: _buildTextSpans(
              description,
              words,
              title.split(' ').length,
            ),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  List<TextSpan> _buildTextSpans(
    String text,
    List<String> allWords,
    int offset,
  ) {
    if (text.trim().isEmpty) return [];

    final words = text.split(' ');
    final spans = <TextSpan>[];

    for (int i = 0; i < words.length; i++) {
      final wordIndex = offset + i;
      final isVisible = wordIndex < _visibleWordCount;

      spans.add(
        TextSpan(
          text: '${words[i]}${i < words.length - 1 ? ' ' : ''}',
          style: TextStyle(
            color: isVisible
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            fontWeight: isVisible ? FontWeight.bold : FontWeight.normal,
            shadows: isVisible
                ? []
                : [
                    Shadow(
                      blurRadius: 1.8,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                  ],
          ),
        ),
      );
    }

    return spans;
  }

  Widget _buildImageCard(int index) {
    final screenSize = MediaQuery.of(context).size;
    final imageSize = screenSize.width * 0.7;

    Widget imageWidget;
    try {
      imageWidget = Image.asset(
        _images[index],
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'Image not available',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      imageWidget = const Center(
        child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
      );
    }

    return Container(
      width: imageSize,
      height: imageSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: imageWidget,
      ),
    );
  }
}
