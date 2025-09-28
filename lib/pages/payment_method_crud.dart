import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class PaymentMethodCrudPage extends StatefulWidget {
  const PaymentMethodCrudPage({super.key});

  @override
  State<PaymentMethodCrudPage> createState() => _PaymentMethodCrudPageState();
}

class _PaymentMethodCrudPageState extends State<PaymentMethodCrudPage> {
  String? _userId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _currencyFormatter = NumberFormat.decimalPattern('id_ID');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is String) {
      if (_userId != arguments) {
        setState(() {
          _userId = arguments;
        });
      }
    }
  }

  // --- LOGIKA UTAMA UNTUK OPERASI CRUD ---

  // Fungsi untuk menampilkan dialog Tambah atau Edit
  void _showAddOrEditDialog({DocumentSnapshot? doc}) {
    final bool isEditing = doc != null;
    final _nameController = TextEditingController(
      text: isEditing ? doc['nama_payment'] : '',
    );
    final _feeController = TextEditingController(
      text: isEditing ? doc['fee'].toString() : '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isEditing ? 'Edit Tujuan Pembayaran' : 'Tambah Tujuan Baru',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama Tujuan'),
              ),
              TextField(
                controller: _feeController,
                decoration: const InputDecoration(
                  labelText: 'Biaya Admin (Fee)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final String name = _nameController.text;
                final int? fee = int.tryParse(_feeController.text);

                if (name.isNotEmpty && fee != null) {
                  final collectionRef = _firestore
                      .collection('users')
                      .doc(_userId)
                      .collection('payment_methods');

                  if (isEditing) {
                    // UPDATE
                    await doc.reference.update({
                      'nama_payment': name,
                      'fee': fee,
                    });
                  } else {
                    // CREATE
                    await collectionRef.add({
                      'nama_payment': name,
                      'fee': fee,
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                  }
                  Navigator.pop(context);
                } else {
                  // Tampilkan pesan error jika form tidak valid
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Harap isi semua field dengan benar.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  // Fungsi untuk menghapus metode pembayaran
  void _deleteMethod(DocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konfirmasi Hapus'),
          content: Text('Anda yakin ingin menghapus "${doc['nama_payment']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await doc.reference.delete();
                Navigator.pop(context);
              },
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
  }

  // --- UI BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atur Tujuan Pembayaran')),
      // Tombol untuk menambah data baru
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOrEditDialog(),
        child: const Icon(Icons.add),
        tooltip: 'Tambah Tujuan Baru',
      ),
      body: _userId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(_userId)
                  .collection('payment_methods')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Belum ada tujuan pembayaran.\nSilakan tambahkan menggunakan tombol (+).',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                // Tampilkan data dalam ListView
                return ListView(
                  padding: const EdgeInsets.all(8.0),
                  children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                      child: ListTile(
                        title: Text(
                          data['nama_payment'] ?? 'Tanpa Nama',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Fee: Rp ${_currencyFormatter.format(data['fee'] ?? 0)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Tombol Edit
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _showAddOrEditDialog(doc: doc),
                            ),
                            // Tombol Hapus
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteMethod(doc),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
