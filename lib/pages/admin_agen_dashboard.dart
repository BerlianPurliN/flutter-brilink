import 'package:brilink/pages/laporan_page.dart';
import 'package:brilink/services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AdminAgenDashboard extends StatefulWidget {
  const AdminAgenDashboard({super.key});

  @override
  State<AdminAgenDashboard> createState() => _AdminAgenDashboardState();
}

class _AdminAgenDashboardState extends State<AdminAgenDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  late Future<List<DocumentSnapshot>> _kasirListFuture;

  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _kasirListFuture = _getManagedKasir();
    }
  }

  /// Fetch kasir documents managed by this admin agen
  Future<List<DocumentSnapshot>> _getManagedKasir() async {
    try {
      final adminAgenDoc =
          await _firestore.collection('users').doc(_currentUser!.uid).get();

      if (!adminAgenDoc.exists) return [];

      final adminData = adminAgenDoc.data() as Map<String, dynamic>;
      final List<dynamic> kasirIds = adminData['managed_kasir_ids'] ?? [];

      if (kasirIds.isEmpty) return [];

      final kasirQuery = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: kasirIds)
          .get();

      return kasirQuery.docs;
    } catch (e) {
      print("Error fetching managed kasir: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Agen Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().signOut();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<DocumentSnapshot>>(
        future: _kasirListFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
          }

          final kasirList = snapshot.data ?? [];

          if (kasirList.isEmpty) {
            return const Center(child: Text('Tidak ada kasir yang dikelola.'));
          }

          return ListView.builder(
            itemCount: kasirList.length,
            itemBuilder: (context, index) {
              final kasirData = kasirList[index].data() as Map<String, dynamic>;
              final kasirEmail = kasirData['email'] ?? 'No Email';
              final kasirId = kasirList[index].id;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(kasirEmail),
                  subtitle: Text('ID: $kasirId'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LaporanPage(userId: kasirId),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
