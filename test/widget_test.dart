// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_chatapp/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App builds and shows splash', (tester) async {
    await tester.pumpWidget(const App());
    // Should at least render a FlutterLogo from SplashScreen
    expect(find.byType(FlutterLogo), findsOneWidget);

    // Let the splash timer finish and navigate to chat
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Ollama Chat (Local)'), findsOneWidget);
  });
}
