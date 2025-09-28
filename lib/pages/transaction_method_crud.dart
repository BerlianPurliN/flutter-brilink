import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// HAPUS 'required this.userId' dari sini
class TransactionMethodsPage extends StatefulWidget {
  const TransactionMethodsPage({super.key});

  @override
  State<TransactionMethodsPage> createState() => _TransactionMethodsPageState();
}

class _TransactionMethodsPageState extends State<TransactionMethodsPage> {
  // Kosongkan referensi koleksi di sini
  late final CollectionReference _methodsCollection;
  // Simpan userId
  late final String userId;

  // UBAH: Gunakan didChangeDependencies untuk mendapatkan argumen sekali saja
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ambil userId dari argumen yang dikirim
    userId = ModalRoute.of(context)!.settings.arguments as String;

    // Inisialisasi referensi koleksi setelah mendapatkan userId
    _methodsCollection = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('transaction_methods');
  }

  // ... (SEMUA FUNGSI CRUD LAINNYA TETAP SAMA: _addMethod, _updateMethod, dll) ...
  // CREATE: Menambahkan metode baru
  Future<void> _addMethod(String methodName) async {
    if (methodName.isNotEmpty) {
      await _methodsCollection.add({
        'metode_transaction': methodName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.of(context).pop(); // Tutup dialog setelah simpan
    }
  }

  // UPDATE: Memperbarui metode yang ada
  Future<void> _updateMethod(DocumentSnapshot doc, String newName) async {
    if (newName.isNotEmpty) {
      await _methodsCollection.doc(doc.id).update({
        'metode_transaction': newName,
      });
      if (mounted) Navigator.of(context).pop(); // Tutup dialog setelah simpan
    }
  }

  // DELETE: Menghapus metode
  Future<void> _deleteMethod(String docId) async {
    await _methodsCollection.doc(docId).delete();
  }

  // Menampilkan dialog untuk Tambah atau Edit
  void _showAddEditDialog({DocumentSnapshot? doc}) {
    final isEditing = doc != null;
    final TextEditingController controller = TextEditingController(
      text: isEditing ? doc!['metode_transaction'] : '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Metode' : 'Tambah Metode Baru'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nama Metode'),
          ),
          actions: [
            TextButton(
              child: const Text('Batal'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Simpan'),
              onPressed: () {
                if (isEditing) {
                  _updateMethod(doc, controller.text);
                } else {
                  _addMethod(controller.text);
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
        title: const Text('Kelola Metode Transaksi'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _methodsCollection
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Terjadi kesalahan.'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada metode transaksi.\nSilakan tambahkan satu.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final methods = snapshot.data!.docs;
          return ListView.builder(
            itemCount: methods.length,
            itemBuilder: (context, index) {
              final doc = methods[index];
              final data = doc.data() as Map<String, dynamic>;
              final methodName =
                  data['metode_transaction'] as String? ?? 'Tidak ada nama';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(methodName),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showAddEditDialog(doc: doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteMethod(doc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        tooltip: 'Tambah Metode',
        child: const Icon(Icons.add),
      ),
    );
  }
}
