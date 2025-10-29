import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:brilink/pages/login_page.dart';
import 'package:brilink/services/auth_service.dart';
import 'package:brilink/widgets/role_router.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Show a loading indicator while connecting to the stream
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If the snapshot has data, the user is logged in
        if (snapshot.hasData) {
          return const RoleRouter();
        }

        // If the snapshot has no data, the user is logged out
        return const LoginPage();
      },
    );
  }
}
