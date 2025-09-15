import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<dynamic> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      // --- Langkah A: Otentikasi Email & Password ---
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final User? user = credential.user;

      if (user == null) {
        return 'Gagal mendapatkan data pengguna setelah otentikasi.';
      }

      // --- Langkah B: Ambil Dokumen Pengguna dari Firestore ---
      final QuerySnapshot userQuery = await _firestore
          .collection('users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      
      // Cek apakah dokumen profil pengguna ada
      if (userQuery.docs.isEmpty) {
        // Jika tidak ada, langsung logout dan beri pesan error
        await _auth.signOut();
        return 'Data profil pengguna tidak ditemukan di database.';
      }

      // --- Langkah C: Validasi Peran (Role) ---
      final userData = userQuery.docs.first.data() as Map<String, dynamic>;
      final String userRole = userData['role'] ?? ''; // Ambil nilai 'role'

      if (userRole == 'customer') {
        // Jika peran adalah 'customer', login berhasil. Kembalikan objek User.
        return user;
      } else {
        // Jika peran BUKAN 'customer', gagalkan login.
        // Logout paksa pengguna agar sesinya tidak menggantung.
        await _auth.signOut();
        return 'Akses ditolak. Hanya customer yang diizinkan login.';
      }

    } on FirebaseAuthException catch (e) {
      // Menangani error otentikasi standar (misal: password salah)
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        return 'Email atau password yang Anda masukkan salah.';
      }
      return e.message ?? 'Terjadi kesalahan saat proses login.';
    } catch (e) {
      return 'Terjadi kesalahan tidak terduga: $e';
    }
  }

  Future<void> signOut() async {
    try {
      // Perintah ini akan menghapus sesi login pengguna dari Firebase
      await _auth.signOut();
    } catch (e) {
      // Menangani jika ada error saat proses logout
      print('Error signing out: $e');
    }
  }
}
