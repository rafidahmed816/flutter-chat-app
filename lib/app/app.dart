import 'package:flutter/material.dart';
import 'package:flutter_chatapp/app/screens/chat_screen.dart';
import 'package:flutter_chatapp/app/screens/onboarding_screen.dart';
import 'package:flutter_chatapp/app/screens/splash_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      routes: {
        OnboardingScreen.routeName: (_) => const OnboardingScreen(),
        ChatScreen.routeName: (_) => const ChatScreen(),
      },
    );
  }
}
