import 'package:brilink/services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  void _showConfirmationDialog(
      String userId, String userEmail, bool currentStatus) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final bool isEnabling = !currentStatus;
        return AlertDialog(
          title: Text('Konfirmasi'),
          content: Text(
              'Apakah Anda yakin ingin ${isEnabling ? 'mengaktifkan' : 'menonaktifkan'} akun $userEmail?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(isEnabling ? 'Aktifkan' : 'Nonaktifkan'),
              onPressed: () async {
                try {
                  await _firestoreService.setUserStatus(userId, isEnabling);
                  Navigator.of(context).pop(); // Close the dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Akun $userEmail berhasil ${isEnabling ? 'diaktifkan' : 'dinonaktifkan'}.'),
                    ),
                  );
                } catch (e) {
                  Navigator.of(context).pop(); // Close the dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal memperbarui status: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Pengguna'),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('users').doc(_currentUserId).get(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (userSnapshot.hasError) {
            return const Center(child: Text('Gagal memuat data pengguna.'));
          }
          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: Text('Pengguna tidak ditemukan.'));
          }

          final currentUserData =
              userSnapshot.data!.data() as Map<String, dynamic>?;
          final currentUserRole = currentUserData?['role'];

          Stream<QuerySnapshot> stream;
          if (currentUserRole == 'super_admin') {
            stream = _firestore.collection('users').where('role',
                whereIn: ['admin_agen', 'super_admin']).snapshots();
          } else if (currentUserRole == 'admin_agen') {
            stream = _firestore
                .collection('users')
                .where('managed_by', isEqualTo: _currentUserId)
                .snapshots();
          } else {
            stream = const Stream.empty();
          }

          return StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Terjadi kesalahan'));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = snapshot.data!.docs;

              if (users.isEmpty) {
                return const Center(
                    child: Text('Tidak ada pengguna untuk ditampilkan.'));
              }

              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final userDoc = users[index];
                  final user = userDoc.data() as Map<String, dynamic>;
                  final userId = userDoc.id;

                  final userEmail = user['email'] ?? 'Tidak ada email';
                  final userRole = user['role'] ?? 'Tidak ada peran';
                  final bool isActive = user['isActive'] ?? true;

                  final bool isCurrentUser = userId == _currentUserId;

                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: isActive ? Colors.white : Colors.grey[350],
                    child: ListTile(
                      title: Text(userEmail),
                      subtitle: Text(
                          'Role: $userRole - Status: ${isActive ? 'Aktif' : 'Nonaktif'}'),
                      trailing: isCurrentUser
                          ? const Chip(label: Text('Anda'))
                          : IconButton(
                              icon: Icon(
                                isActive ? Icons.no_accounts : Icons.how_to_reg,
                                color: isActive ? Colors.red : Colors.green,
                              ),
                              tooltip: isActive ? 'Nonaktifkan' : 'Aktifkan',
                              onPressed: () {
                                _showConfirmationDialog(
                                    userId, userEmail, isActive);
                              },
                            ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
