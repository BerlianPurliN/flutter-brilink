import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> createDefaultDataIfNotExist(User user) async {
    print(
        "DEBUG: Fungsi createDefaultDataIfNotExist DIMULAI untuk user ${user.uid}");
    try {
      final rekeningCollection =
          _db.collection('users').doc(user.uid).collection('rekening');
      final rekeningSnapshot = await rekeningCollection.limit(1).get();
      print(
          "DEBUG: Cek rekening... Apakah snapshot kosong? ${rekeningSnapshot.docs.isEmpty}");

      if (rekeningSnapshot.docs.isEmpty) {
        print("DEBUG: MEMBUAT dokumen rekening default...");
        await rekeningCollection.add({
          'nama_rekening': 'Rekening Utama',
          'saldo': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print("DEBUG: Dokumen rekening default SELESAI dibuat. ${user.uid}");
      }
      final cashCollection =
          _db.collection('users').doc(user.uid).collection('cash');
      final cashSnapshot = await cashCollection.limit(1).get();
      print(
          "DEBUG: Cek cash... Apakah snapshot kosong? ${cashSnapshot.docs.isEmpty}");

      if (cashSnapshot.docs.isEmpty) {
        print("DEBUG: MEMBUAT dokumen kas tunai default...");
        await cashCollection.add({
          'nama_kas': 'Kas Tunai',
          'saldo': 0, // Saldo awal selalu 0
          'createdAt': FieldValue.serverTimestamp(),
        });
        print("DEBUG: Dokumen kas tunai SELESAI dibuat. ${user.uid}");
      }
    } catch (e) {
      // PERBAIKAN #2: Cetak error dengan lebih jelas dan lemparkan kembali
      print("---!!! ERROR DI CREATE DEFAULT DATA: $e !!!---");
      throw Exception(
          'Gagal menyiapkan data awal pengguna. Periksa Firestore Rules.');
    }
  }

  Future<void> initializeUserTransactionMethods(
      {required String userId}) async {
    try {
      // 1. Buat referensi ke sub-koleksi
      final subCollectionRef =
          _db.collection('users').doc(userId).collection('transaction_methods');

      // 2. Lakukan query untuk memeriksa apakah ada dokumen di dalamnya

      final snapshot = await subCollectionRef.limit(1).get();

      // 3. Jika tidak ada dokumen (koleksi kosong atau belum ada)
      if (snapshot.docs.isEmpty) {
        print(
            'Sub-koleksi transaction_methods belum ada. Membuat placeholder...');

        // 4. Tambahkan satu dokumen placeholder
        await subCollectionRef.add({
          'metode_transaction': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('Dokumen placeholder berhasil dibuat.');
      } else {
        print('Sub-koleksi transaction_methods sudah ada. Tidak ada tindakan.');
      }
    } catch (e) {
      print('Terjadi error saat inisialisasi sub-koleksi: $e');
    }
  }
}
