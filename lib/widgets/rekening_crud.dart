import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class RekeningCrudDialog extends StatefulWidget {
  final String userId;

  const RekeningCrudDialog({super.key, required this.userId});

  @override
  State<RekeningCrudDialog> createState() => _RekeningCrudDialogState();
}

class _RekeningCrudDialogState extends State<RekeningCrudDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _currencyFormatter = NumberFormat.decimalPattern('id_ID');

  // Fungsi untuk menampilkan dialog Tambah atau Edit
  void _showAddOrEditDialog({DocumentSnapshot? doc}) {
    final bool isEditing = doc != null;
    final _nameController = TextEditingController(
      text: isEditing ? doc['nama_rekening'] : '',
    );
    final _balanceController = TextEditingController(
      text: isEditing ? doc['saldo'].toString() : '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Rekening' : 'Tambah Rekening Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama Rekening'),
              ),
              TextField(
                controller: _balanceController,
                decoration: const InputDecoration(labelText: 'Saldo Awal'),
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
                final int? balance = int.tryParse(_balanceController.text);

                if (name.isNotEmpty && balance != null) {
                  final collectionRef = _firestore
                      .collection('users')
                      .doc(widget.userId)
                      .collection('rekening');
                  if (isEditing) {
                    await doc.reference.update({
                      'nama_rekening': name,
                      'saldo': balance,
                    });
                  } else {
                    await collectionRef.add({
                      'nama_rekening': name,
                      'saldo': balance,
                    });
                  }
                  Navigator.pop(context);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  // Fungsi untuk menghapus rekening
  void _deleteRekening(DocumentSnapshot doc) {
    // Hanya izinkan hapus jika saldo 0 untuk keamanan
    if ((doc['saldo'] as num) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hanya rekening dengan saldo 0 yang bisa dihapus.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: Text(
          'Anda yakin ingin menghapus rekening "${doc['nama_rekening']}"?',
        ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Atur Rekening'),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('users')
              .doc(widget.userId)
              .collection('rekening')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            return ListView(
              shrinkWrap: true,
              children: snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return Card(
                  child: ListTile(
                    title: Text(data['nama_rekening'] ?? ''),
                    subtitle: Text(
                      'Saldo: Rp ${_currencyFormatter.format(data['saldo'] ?? 0)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showAddOrEditDialog(doc: doc),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteRekening(doc),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Tambah Rekening Baru'),
          onPressed: () => _showAddOrEditDialog(),
        ),
      ],
    );
  }
}
