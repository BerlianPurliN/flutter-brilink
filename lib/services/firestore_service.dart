import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Memeriksa apakah pengguna sudah memiliki data, dan membuat rekening default jika belum.
  Future<void> createDefaultDataIfNotExist(User user) async {
    try {
      // 1. Tentukan path ke sub-koleksi 'rekening' milik pengguna
      final rekeningCollection = _db
          .collection('users')
          .doc(user.uid)
          .collection('rekening');

      final snapshot = await rekeningCollection.limit(1).get();

      if (snapshot.docs.isEmpty) {
        // Buat satu dokumen rekening default
        await rekeningCollection.add({
          'nama_rekening': 'Dompet Utama',
          'saldo': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('Default rekening created for user ${user.uid}');
      } else {
        print('User ${user.uid} already has rekening data.');
      }
    } catch (e) {
      print('Error creating default data: $e');
    }
  }
}
