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
  // Ganti ke Future<List<DocumentSnapshot>> agar sesuai dengan return type
  late Future<List<DocumentSnapshot>> _kasirListFuture;

  @override
  void initState() {
    super.initState();
    print("initState: AdminAgenDashboard"); // DEBUG
    if (_currentUser != null) {
      print("initState: _currentUser UID: ${_currentUser!.uid}"); // DEBUG
      _kasirListFuture = _getManagedKasir();
    } else {
      print("initState: _currentUser is null!"); // DEBUG
      // Handle kasus user null, mungkin lempar error atau set future ke error
      _kasirListFuture = Future.value([]); // Atau Future.error(...)
    }
  }

  // Fetch kasir documents managed by this admin agen
  Future<List<DocumentSnapshot>> _getManagedKasir() async {
    print("--- DEBUG: Starting TEMP read test ---");
    if (_currentUser == null) {
      print("--- DEBUG: TEMP read - User null ---");
      return [];
    }
    final String adminAgenId = _currentUser!.uid;
    try {
      print("--- DEBUG: Attempting to GET users/$adminAgenId ---");
      final doc = await _firestore.collection('users').doc(adminAgenId).get();
      if (doc.exists) {
        print("--- DEBUG: TEMP read SUCCESS - Doc data: ${doc.data()} ---");
        // Return a list containing just this doc for testing UI
        return [doc];
      } else {
        print("--- DEBUG: TEMP read FAILED - Doc doesn't exist ---");
        return [];
      }
    } catch (e) {
      print("--- ERROR: TEMP read FAILED - Error: $e ---");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Anda sudah punya print ini
    print("UID Admin Agen yang sedang login: ${_currentUser?.uid}");

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
      // Menggunakan FutureBuilder karena _getManagedKasir adalah Future
      body: FutureBuilder<List<DocumentSnapshot>>(
        future: _kasirListFuture,
        builder: (context, snapshot) {
          print(
              "FutureBuilder: Connection State: ${snapshot.connectionState}"); // DEBUG
          if (snapshot.connectionState == ConnectionState.waiting) {
            print("FutureBuilder: Menunggu future selesai..."); // DEBUG
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            print("FutureBuilder: Error: ${snapshot.error}"); // DEBUG
            return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
          }

          // Gunakan snapshot.data (hasil dari future)
          final kasirList = snapshot.data ?? [];
          print(
              "FutureBuilder: Data diterima. Jumlah kasir: ${kasirList.length}"); // DEBUG

          if (kasirList.isEmpty) {
            print("FutureBuilder: Tidak ada kasir yang dikelola."); // DEBUG
            // Tambahkan tombol Lihat Laporan Gabungan di sini juga
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Tidak ada kasir yang dikelola.'),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.bar_chart),
                      label: const Text('Lihat Laporan Saya (Jika Ada)'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 24),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/laporan',
                          arguments:
                              _currentUser!.uid, // Kirim ID Admin Agen sendiri
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          // Jika ada kasir, tampilkan ListView dan Tombol Laporan
          return Column(
            // Bungkus dengan Column
            children: [
              // Tombol Laporan Gabungan
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('Lihat Laporan Gabungan'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/laporan',
                        arguments:
                            _currentUser!.uid, // Kirim ID Admin Agen sendiri
                      );
                    },
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Divider(),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kasir yang Dikelola:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // Daftar Kasir
              Expanded(
                // Bungkus ListView dengan Expanded
                child: ListView.builder(
                  itemCount: kasirList.length,
                  itemBuilder: (context, index) {
                    final kasirData =
                        kasirList[index].data() as Map<String, dynamic>;
                    final kasirEmail = kasirData['email'] ?? 'No Email';
                    final kasirId = kasirList[index].id;
                    final kasirName = kasirData['name']; // Ambil nama jika ada

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4), // Margin diperkecil
                      child: ListTile(
                        leading: const CircleAvatar(
                            child:
                                Icon(Icons.person_outline)), // Icon lebih bagus
                        // Tampilkan Nama jika ada, fallback ke Email
                        title: Text(kasirName ?? kasirEmail,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle:
                            Text(kasirEmail), // Tampilkan email di subtitle
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          // Navigasi ke LaporanPage KHUSUS untuk kasir ini
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              // Di LaporanPage, query harus pakai uid_user == kasirId
                              // Perlu modifikasi LaporanPage jika ingin view per kasir
                              builder: (context) =>
                                  LaporanPage(userId: kasirId),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
