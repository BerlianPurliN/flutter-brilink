import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CashCrudDialog extends StatefulWidget {
  final String userId;

  const CashCrudDialog({super.key, required this.userId});

  @override
  State<CashCrudDialog> createState() => _CashCrudDialogState();
}

class _CashCrudDialogState extends State<CashCrudDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _currencyFormatter = NumberFormat.decimalPattern('id_ID');

  // Fungsi untuk menampilkan dialog Tambah atau Edit Kas
  void _showAddOrEditDialog({DocumentSnapshot? doc}) {
    final bool isEditing = doc != null;
    final _nameController =
        TextEditingController(text: isEditing ? doc['nama_kas'] : '');
    final _balanceController =
        TextEditingController(text: isEditing ? doc['saldo'].toString() : '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Kas Tunai' : 'Tambah Kas Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Nama Kas (cth: Kas Toko)'),
              ),
              TextField(
                controller: _balanceController,
                decoration: const InputDecoration(labelText: 'Saldo Saat Ini'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final String name = _nameController.text;
                final int? balance = int.tryParse(_balanceController.text);

                if (name.isNotEmpty && balance != null) {
                  final collectionRef = _firestore
                      .collection('users')
                      .doc(widget.userId)
                      .collection('cash');
                  if (isEditing) {
                    await doc.reference
                        .update({'nama_kas': name, 'saldo': balance});
                  } else {
                    await collectionRef.add({
                      'nama_kas': name,
                      'saldo': balance,
                      'createdAt': FieldValue.serverTimestamp()
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

  // Fungsi untuk menghapus kas
  void _deleteCash(DocumentSnapshot doc) {
    if ((doc['saldo'] as num) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Hanya kas dengan saldo 0 yang bisa dihapus.'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: Text('Anda yakin ingin menghapus kas "${doc['nama_kas']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await doc.reference.delete();
              Navigator.pop(context);
            },
            child: const Text('Hapus'),
          )
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
          const Text('Atur Kas Tunai'),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('users')
              .doc(widget.userId)
              .collection('cash')
              .orderBy('createdAt')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.data!.docs.isEmpty)
              return const Center(child: Text('Belum ada kas tunai.'));

            return ListView(
              shrinkWrap: true,
              children: snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return Card(
                  child: ListTile(
                    title: Text(data['nama_kas'] ?? ''),
                    subtitle: Text(
                        'Saldo: Rp ${_currencyFormatter.format(data['saldo'] ?? 0)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showAddOrEditDialog(doc: doc)),
                        IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteCash(doc)),
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
          label: const Text('Tambah Kas Baru'),
          onPressed: () => _showAddOrEditDialog(),
        )
      ],
    );
  }
}
