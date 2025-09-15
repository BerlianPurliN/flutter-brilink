import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

enum FilterType { none, byMethod, byDateRange }

class LaporanPage extends StatefulWidget {
  const LaporanPage({super.key});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _currencyFormatter = NumberFormat.decimalPattern('id_ID');
  bool _isProcessing = false;
  String? _selectedFilterMethod;
  String? _userId;

  FilterType _activeFilter = FilterType.none;
  String? _selectedMethod; // Untuk filter berdasarkan metode
  DateTimeRange? _selectedDateRange;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is String) {
      if (_userId != arguments) {
        print("--- DEBUG 1: User ID diterima di LaporanPage ---");
        print("UserID: $arguments");
        setState(() {
          _userId = arguments;
        });
      }
    } else {
      print(
        "--- DEBUG 1.1: Tidak ada User ID yang diterima di LaporanPage ---",
      );
    }
  }

  Future<void> _exportToExcel(List<QueryDocumentSnapshot> transactions) async {
    print("--- DEBUG: Memulai proses ekspor... ---");
    if (_isProcessing) return;

    if (transactions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada data untuk diekspor.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. Meminta Izin Penyimpanan
      var status = await Permission.storage.request();

      // 2. Menangani Status Izin
      if (status.isGranted) {
        print("--- DEBUG: Izin diberikan. Membuat file Excel... ---");
        // Membuat file Excel
        var excel = Excel.createExcel();
        Sheet sheetObject = excel['Laporan Transaksi'];

        // Menambahkan header
        sheetObject.appendRow([
          TextCellValue('Tanggal'),
          TextCellValue('Metode Pembayaran'),
          TextCellValue('Rekening Sumber'),
          TextCellValue('Harga Beli'),
          TextCellValue('Harga Jual Admin'),
          TextCellValue('Biaya Admin'),
          TextCellValue('Uang Bersih (Profit)'),
        ]);

        // Menambahkan data baris
        for (var doc in transactions) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
          final formattedDate = timestamp != null
              ? DateFormat('dd-MM-yyyy HH:mm').format(timestamp)
              : 'N/A';

          sheetObject.appendRow([
            TextCellValue(formattedDate),
            TextCellValue(data['nama_payment_method'] ?? ''),
            TextCellValue(data['nama_rekening'] ?? ''),
            IntCellValue((data['harga_beli'] as num?)?.toInt() ?? 0),
            IntCellValue((data['harga_jual_admin'] as num?)?.toInt() ?? 0),
            IntCellValue((data['biaya_admin'] as num?)?.toInt() ?? 0),
            IntCellValue((data['uang_bersih'] as num?)?.toInt() ?? 0),
          ]);
        }

        // 3. Menyimpan File ke Direktori 'Downloads'
        String? selectedDirectory =
            await FilePicker.platform.getDirectoryPath();

        if (selectedDirectory == null) {
          // Pengguna membatalkan pemilihan folder
          print("--- DEBUG: Pengguna membatalkan pemilihan folder. ---");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ekspor dibatalkan.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() {
            _isProcessing = false;
          });
          return;
        }

        final fileName =
            'laporan_transaksi_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
        final filePath = '$selectedDirectory/$fileName';
        final file = File(filePath);

        final excelData = excel.encode();
        if (excelData != null) {
          await file.writeAsBytes(excelData);
          print("--- DEBUG: File berhasil disimpan di: $filePath ---");
        }
      } else if (status.isPermanentlyDenied) {
        print("--- DEBUG: Izin ditolak permanen. ---");
        // Jika izin ditolak permanen, arahkan pengguna ke pengaturan
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Izin penyimpanan ditolak permanen. Aktifkan di pengaturan aplikasi.',
              ),
              action: SnackBarAction(
                label: 'Pengaturan',
                onPressed: openAppSettings,
              ),
            ),
          );
        }
      } else {
        print("--- DEBUG: Izin ditolak. ---");
        // Jika izin hanya ditolak
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin penyimpanan diperlukan untuk ekspor.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("--- ERROR SAAT EKSPOR: $e ---");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Filter Transaksi",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.payment),
                title: const Text("Berdasarkan Metode Pembayaran"),
                onTap: () async {
                  Navigator.pop(context); // Tutup bottom sheet
                  await _showMethodFilterDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: const Text("Berdasarkan Rentang Tanggal"),
                onTap: () {
                  Navigator.pop(context); // Tutup bottom sheet
                  _showDateRangePicker();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.clear_all, color: Colors.red),
                title: const Text(
                  "Hapus Semua Filter",
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  setState(() {
                    _activeFilter = FilterType.none;
                    _selectedMethod = null;
                    _selectedDateRange = null;
                  });
                  Navigator.pop(context); // Tutup bottom sheet
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMethodFilterDialog() async {
    if (_userId == null) return;
    final snapshot = await _firestore
        .collection('transactions')
        .where('uid_user', isEqualTo: _userId)
        .get();
    final availableMethods = [
      ...snapshot.docs
          .map((doc) => (doc.data())['nama_payment_method'] as String)
          .toSet()
          .toList(),
    ];

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pilih Metode'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableMethods.length,
              itemBuilder: (context, index) {
                final method = availableMethods[index];
                return ListTile(
                  title: Text(method),
                  onTap: () {
                    setState(() {
                      _activeFilter = FilterType.byMethod;
                      _selectedMethod = method;
                      _selectedDateRange = null; // Reset filter lain
                    });
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDateRangePicker() async {
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );

    if (pickedRange != null) {
      setState(() {
        _activeFilter = FilterType.byDateRange;
        _selectedDateRange = pickedRange;
        _selectedMethod = null; // Reset filter lain
      });
    }
  }

  void _showFilterDialog(List<String> availableMethods) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter Berdasarkan Metode'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableMethods.length,
              itemBuilder: (context, index) {
                final method = availableMethods[index];
                return ListTile(
                  title: Text(method),
                  onTap: () {
                    setState(() {
                      if (method == 'Semua') {
                        _selectedFilterMethod = null; // Hapus filter
                      } else {
                        _selectedFilterMethod = method; // Terapkan filter
                      }
                    });
                    Navigator.of(context).pop(); // Tutup dialog
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteTransaction(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final hargaBeli = data['harga_beli'] as int;
    final rekeningId = data['uid_rekening'] as String;

    // Tampilkan dialog konfirmasi terlebih dahulu
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: const Text(
          'Anda yakin ingin menghapus transaksi ini? Saldo rekening akan dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final rekeningRef = _firestore
            .collection('users')
            .doc(_userId)
            .collection('rekening')
            .doc(rekeningId);

        WriteBatch batch = _firestore.batch();

        // Operasi 1: Kembalikan saldo sebesar harga_beli ke rekening
        batch.update(rekeningRef, {'saldo': FieldValue.increment(hargaBeli)});

        // Operasi 2: Hapus dokumen transaksi
        batch.delete(doc.reference);

        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaksi berhasil dihapus.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menghapus: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showEditTransactionDialog(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final _hargaBeliController = TextEditingController(
      text: data['harga_beli'].toString(),
    );
    final _hargaJualController = TextEditingController(
      text: data['harga_jual_admin'].toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Transaksi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Metode: ${data['nama_payment_method']}",
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hargaBeliController,
                decoration: const InputDecoration(labelText: 'Harga Beli'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _hargaJualController,
                decoration: const InputDecoration(
                  labelText: 'Harga Jual Admin',
                ),
                keyboardType: TextInputType.number,
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
                final int oldHargaBeli = data['harga_beli'];
                final int? newHargaBeli = int.tryParse(
                  _hargaBeliController.text,
                );
                final int? newHargaJual = int.tryParse(
                  _hargaJualController.text,
                );

                if (newHargaBeli != null && newHargaJual != null) {
                  // Hitung ulang uang bersih
                  final int biayaAdmin = data['biaya_admin'];
                  final int newUangBersih =
                      (newHargaJual - biayaAdmin) - newHargaBeli;

                  // Hitung selisih untuk penyesuaian saldo
                  final int deltaSaldo = oldHargaBeli - newHargaBeli;

                  try {
                    final rekeningRef = _firestore
                        .collection('users')
                        .doc(_userId)
                        .collection('rekening')
                        .doc(data['uid_rekening']);

                    WriteBatch batch = _firestore.batch();

                    // Operasi 1: Update dokumen transaksi dengan nilai baru
                    batch.update(doc.reference, {
                      'harga_beli': newHargaBeli,
                      'harga_jual_admin': newHargaJual,
                      'uang_bersih': newUangBersih,
                    });

                    // Operasi 2: Sesuaikan saldo rekening dengan selisihnya
                    batch.update(rekeningRef, {
                      'saldo': FieldValue.increment(deltaSaldo),
                    });

                    await batch.commit();

                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal update: $e')),
                      );
                    }
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _showTransactionDetailDialog(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final formattedDate = timestamp != null
        ? DateFormat('EEEE, dd MMMM yyyy, HH:mm', 'id_ID').format(timestamp)
        : 'N/A';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Detail Transaksi'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Tanggal', formattedDate),
                _buildDetailRow(
                  'Metode Pembayaran',
                  data['nama_payment_method'] ?? '-',
                ),
                _buildDetailRow(
                  'Rekening Sumber',
                  data['nama_rekening'] ?? '-',
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  'Harga Beli',
                  'Rp ${_currencyFormatter.format(data['harga_beli'] ?? 0)}',
                ),
                _buildDetailRow(
                  'Harga Jual Admin',
                  'Rp ${_currencyFormatter.format(data['harga_jual_admin'] ?? 0)}',
                ),
                _buildDetailRow(
                  'Biaya Admin',
                  'Rp ${_currencyFormatter.format(data['biaya_admin'] ?? 0)}',
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  'Uang Bersih (Profit)',
                  'Rp ${_currencyFormatter.format(data['uang_bersih'] ?? 0)}',
                  isBold: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Transaksi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
          ),
        ],
      ),
      body: _userId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: () {
                Query query = _firestore
                    .collection('transactions')
                    .where('uid_user', isEqualTo: _userId);

                // Menerapkan filter secara dinamis ke query Firestore
                switch (_activeFilter) {
                  case FilterType.byMethod:
                    if (_selectedMethod != null) {
                      query = query.where(
                        'nama_payment_method',
                        isEqualTo: _selectedMethod,
                      );
                    }
                    break;
                  case FilterType.byDateRange:
                    if (_selectedDateRange != null) {
                      query = query
                          .where(
                            'timestamp',
                            isGreaterThanOrEqualTo: _selectedDateRange!.start,
                          )
                          .where(
                            'timestamp',
                            isLessThanOrEqualTo: _selectedDateRange!.end.add(
                              const Duration(days: 1),
                            ),
                          );
                    }
                    break;
                  case FilterType.none:
                    break;
                }

                return query.orderBy('timestamp', descending: true).snapshots();
              }(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print("--- ERROR DARI FIREBASE ---");
                  print(snapshot.error);
                  print("---------------------------");
                  return Center(
                    child: Text('Gagal memuat data: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Tidak ada transaksi yang cocok dengan filter.',
                    ),
                  );
                }

                final transactions = snapshot.data!.docs;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: _isProcessing
                              ? Container(
                                  width: 20,
                                  height: 20,
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: Text(
                            _isProcessing ? 'MEMPROSES...' : 'Export ke Excel',
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () => _exportToExcel(transactions),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor:
                                _isProcessing ? Colors.grey : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(
                              label: Text(
                                'Tanggal',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Metode',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Aksi',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          rows: transactions.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final timestamp =
                                (data['timestamp'] as Timestamp?)?.toDate();
                            final formattedDate = timestamp != null
                                ? DateFormat('dd/MM/yy HH:mm').format(timestamp)
                                : 'N/A';
                            return DataRow(
                              cells: [
                                DataCell(Text(formattedDate)),
                                DataCell(
                                  Text(data['nama_payment_method'] ?? ''),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.visibility,
                                          color: Colors.teal,
                                          size: 20,
                                        ),
                                        tooltip: 'Lihat Detail',
                                        onPressed: () =>
                                            _showTransactionDetailDialog(doc),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.blue,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          _showEditTransactionDialog(doc);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          _deleteTransaction(doc);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
