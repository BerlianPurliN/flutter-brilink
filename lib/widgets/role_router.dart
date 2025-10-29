
import 'package:brilink/pages/admin_agen_dashboard.dart';
import 'package:brilink/pages/home_page.dart';
import 'package:brilink/pages/super_admin_dashboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  Future<DocumentSnapshot?>? _userDataFuture;

  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _userDataFuture = _getUserData();
    }
  }

  Future<DocumentSnapshot?> _getUserData() async {
    try {
      final userDoc =
          await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        return userDoc;
      }
    } catch (e) {
      print("Error getting user data: $e");
      // Sign out on error to prevent unauthorized access
      await FirebaseAuth.instance.signOut();
      return null;
    }
    // Also sign out if user document doesn't exist
    await FirebaseAuth.instance.signOut();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      // Should be handled by AuthWrapper, but as a fallback
      return const Scaffold(
        body: Center(
          child: Text('Sesi tidak ditemukan. Silakan login kembali.'),
        ),
      );
    }

    return FutureBuilder<DocumentSnapshot?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          // Error or no document, user is already signed out by _getUserData
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Gagal memuat data pengguna atau akun tidak ditemukan. Anda telah dikeluarkan.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>?;

        // Check if account is active. Default to true if field is missing.
        final bool isActive = userData?['isActive'] ?? true;

        if (!isActive) {
          // If not active, sign out and show a message
          // The future needs to complete, so we do it in a post-frame callback
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await FirebaseAuth.instance.signOut();
            // Optionally show a dialog or navigate to a specific "account disabled" page
          });

          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Akun Anda telah dinonaktifkan. Silakan hubungi administrator.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final role = userData?['role'] as String?;

        switch (role) {
          case 'kasir':
            return const HomePage();
          case 'customer': // Legacy role
            return const HomePage();
          case 'admin_agen':
            return const AdminAgenDashboard();
          case 'super_admin':
            return const SuperAdminDashboard();
          default:
            // Sign out if role is unknown
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await FirebaseAuth.instance.signOut();
            });
            return const Scaffold(
              body: Center(
                child: Text('Peran tidak dikenali. Hubungi administrator.'),
              ),
            );
        }
      },
    );
  }
}
