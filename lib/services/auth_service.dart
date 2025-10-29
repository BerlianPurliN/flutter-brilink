import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart'; // <-- 1. IMPORT TAMBAHAN

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Helper untuk mendapatkan user saat ini (untuk debugging)
  User? get currentUser => _auth.currentUser;

  // --- signInWithEmailAndPassword (Tidak Berubah) ---
  Future<dynamic> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final User? user = credential.user;

      if (user == null) {
        return 'Gagal mendapatkan data pengguna setelah otentikasi.';
      }

      final QuerySnapshot userQuery = await _firestore
          .collection('users')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        await _auth.signOut();
        return 'Data profil pengguna tidak ditemukan di database.';
      }
      return user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        return 'Email atau password yang Anda masukkan salah.';
      }
      return e.message ?? 'Terjadi kesalahan saat proses login.';
    } catch (e) {
      return 'Terjadi kesalahan tidak terduga: $e';
    }
  }

  // --- signOut (Tidak Berubah) ---
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  // --- createUser (DIPERBAIKI) ---
  Future<String?> createUser({
    required String email,
    required String password,
    required String role,
    String? adminAgenId,
  }) async {
    // 2. Buat instance Aplikasi Firebase sekunder sementara
    FirebaseApp tempApp;
    try {
      // Coba dapatkan jika sudah ada (misal dari error sebelumnya)
      tempApp = Firebase.app('secondary');
    } catch (e) {
      // Jika tidak ada, inisialisasi
      tempApp = await Firebase.initializeApp(
        name: 'secondary',
        options: Firebase.app().options, // Gunakan config yang sama
      );
    }

    try {
      // 3. Buat user menggunakan instance auth dari aplikasi sekunder
      // Ini TIDAK akan mengubah status login di aplikasi utama Anda
      UserCredential userCredential =
          await FirebaseAuth.instanceFor(app: tempApp)
              .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        // 4. Simpan data ke Firestore (menggunakan instance utama)
        // Karena aplikasi utama masih login sebagai super_admin, ini akan BERHASIL
        Map<String, dynamic> newUserData = {
          'uid': user.uid,
          'email': email,
          'role': role,
        };

        if (role == 'kasir' && adminAgenId != null) {
          await _firestore.runTransaction((transaction) async {
            final newUserDocRef = _firestore.collection('users').doc(user.uid);
            newUserData['managed_by'] = adminAgenId;

            final adminAgenDocRef =
                _firestore.collection('users').doc(adminAgenId);
            transaction.update(adminAgenDocRef, {
              'managed_kasir_ids': FieldValue.arrayUnion([user.uid])
            });
            transaction.set(newUserDocRef, newUserData);
          });
        } else {
          await _firestore.collection('users').doc(user.uid).set(newUserData);
        }

        // 5. Hapus aplikasi sementara setelah selesai
        await tempApp.delete();
        return null; // Sukses
      }

      await tempApp.delete();
      return "User creation failed.";
    } on FirebaseAuthException catch (e) {
      await tempApp.delete(); // Bersihkan jika gagal
      return e.message;
    } catch (e) {
      await tempApp.delete(); // Bersihkan jika gagal
      return e.toString();
    }
  }
}
