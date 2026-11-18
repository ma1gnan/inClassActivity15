import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'sign_in_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.signedInBuilder,
    this.authStateStream,
  });

  final Widget Function(User user) signedInBuilder;
  final Stream<User?>? authStateStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authStateStream ?? FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Authentication state unavailable.')),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const SignInScreen();
        }

        return signedInBuilder(user);
      },
    );
  }
}
