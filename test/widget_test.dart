import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:science_quiz/screens/auth_gate.dart';

void main() {
  testWidgets('Science Signal authentication loading state', (
    WidgetTester tester,
  ) async {
    final authController = StreamController<dynamic>.broadcast();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          authStateStream: authController.stream.cast(),
          signedInBuilder: (user) => const Scaffold(body: Text('Quiz loaded')),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());

    await authController.close();
  });
}
