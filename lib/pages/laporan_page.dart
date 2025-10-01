import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
    print("--- DEBUG: Memulai proses ekspor Excel... ---");
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
      // 1. Buat file Excel
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Laporan Transaksi'];

      // Header
      sheetObject.appendRow([
        TextCellValue('Tanggal'),
        TextCellValue('Metode Pembayaran'),
        TextCellValue('Rekening Saldo'),
        TextCellValue('Rekening Cash'),
        TextCellValue('Harga Beli'),
        TextCellValue('Biaya Admin Dalam'),
        TextCellValue('Biaya Admin'),
        TextCellValue('Uang Bersih (Profit)'),
      ]);

      // Data baris
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
          TextCellValue(data['nama_cash'] ?? ''),
          TextCellValue(
              'Rp ${_currencyFormatter.format((data['harga_beli'] as num?)?.toInt() ?? 0)}'),
          TextCellValue(
              'Rp ${_currencyFormatter.format((data['harga_jual_admin'] as num?)?.toInt() ?? 0)}'),
          TextCellValue(
              'Rp ${_currencyFormatter.format((data['biaya_admin'] as num?)?.toInt() ?? 0)}'),
          TextCellValue(
              'Rp ${_currencyFormatter.format((data['uang_profit'] as num?)?.toInt() ?? 0)}'),
        ]);
      }

      // 2. Encode Excel ke bytes
      final excelBytes = excel.encode();
      if (excelBytes == null) throw Exception("Gagal mengenerate Excel.");

      // 3. Simpan dengan FileSaver
      final fileName =
          'laporan_transaksi_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

      final savedPath = await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(excelBytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      print("--- DEBUG: Excel berhasil diekspor: $savedPath ---");

      // 4. Langsung buka file setelah berhasil disimpan
      if (savedPath != null) {
        await OpenFilex.open(savedPath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File Excel berhasil diekspor: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("--- ERROR SAAT EKSPOR EXCEL: $e ---");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor Excel: $e'),
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
                  labelText: 'Biaya Admin Dalam',
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
                  'Metode Transaksi',
                  data['nama_transaction_method'] ?? '-',
                ),
                _buildDetailRow(
                  'Metode Pembayaran',
                  data['nama_payment_method'] ?? '-',
                ),
                _buildDetailRow(
                  'Rekening Saldo',
                  data['nama_rekening'] ?? '-',
                ),
                _buildDetailRow(
                  'Rekening Cash',
                  data['nama_cash'] ?? '-',
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  'Harga Beli',
                  'Rp ${_currencyFormatter.format(data['harga_beli'] ?? 0)}',
                ),
                _buildDetailRow(
                  'Biaya Admin Dalam',
                  'Rp ${_currencyFormatter.format(data['harga_jual_admin'] ?? 0)}',
                ),
                _buildDetailRow(
                  'Biaya Admin',
                  'Rp ${_currencyFormatter.format(data['biaya_admin'] ?? 0)}',
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  'Uang Bersih (Profit)',
                  'Rp ${_currencyFormatter.format(data['uang_profit'] ?? 0)}',
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

  Future<void> _exportToPdf(List<QueryDocumentSnapshot> transactions) async {
    print("--- DEBUG: Memulai proses ekspor PDF... ---");
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
      print("--- DEBUG: Membuat file PDF... ---");

      final font = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
      final boldFont = await rootBundle.load("assets/fonts/Roboto-Bold.ttf");
      final ttf = pw.Font.ttf(font);
      final boldTtf = pw.Font.ttf(boldFont);

      final pdf = pw.Document();

      final headers = [
        'Tanggal',
        'Metode',
        'Rekening Saldo',
        'Rekening Cash',
        'Harga Beli',
        'Biaya Admin Dalam',
        'Biaya Admin Layanan',
        'Profit'
      ];
      final data = transactions.map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        final timestamp = (d['timestamp'] as Timestamp?)?.toDate();
        final date = timestamp != null
            ? DateFormat('dd/MM/yy HH:mm').format(timestamp)
            : 'N/A';
        final method = d['nama_payment_method'] ?? '-';
        final rekening = d['nama_rekening'] ?? '-';
        final rekeningCash = d['nama_cash'] ?? '-';
        final hargaBeli =
            'Rp ${_currencyFormatter.format(d['harga_beli'] ?? 0)}';
        final hargaJual =
            'Rp ${_currencyFormatter.format(d['harga_jual_admin'] ?? 0)}';
        final biayaAdmin =
            'Rp ${_currencyFormatter.format(d['biaya_admin'] ?? 0)}';
        final profit = 'Rp ${_currencyFormatter.format(d['uang_profit'] ?? 0)}';
        return [
          date,
          method,
          rekening,
          rekeningCash,
          hargaBeli,
          hargaJual,
          biayaAdmin,
          profit
        ];
      }).toList();

      final totalProfit = transactions.fold<int>(0, (sum, doc) {
        final d = doc.data() as Map<String, dynamic>;
        return sum + ((d['uang_profit'] as num?)?.toInt() ?? 0);
      });

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (context) => pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Text('Laporan Transaksi',
                style: pw.TextStyle(font: boldTtf, fontSize: 24)),
          ),
          build: (context) => [
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(font: boldTtf, color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey700),
              cellStyle: pw.TextStyle(font: ttf, fontSize: 10),
              cellAlignments: {
                3: pw.Alignment.centerRight,
              },
            ),
            pw.Divider(height: 20),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total Profit: Rp ${_currencyFormatter.format(totalProfit)}',
                style: pw.TextStyle(font: boldTtf, fontSize: 14),
              ),
            )
          ],
          footer: (context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Halaman ${context.pageNumber} dari ${context.pagesCount}',
              style: pw.TextStyle(
                font: ttf,
                fontSize: 8,
                color: PdfColors.grey,
              ),
            ),
          ),
        ),
      );

      // 🔑 Simpan dengan FileSaver
      final pdfBytes = await pdf.save();
      final fileName =
          'laporan_transaksi_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';

      final savedPath = await FileSaver.instance.saveFile(
        name: fileName,
        bytes: pdfBytes,
        ext: "pdf",
        mimeType: MimeType.pdf,
      );

      print("--- DEBUG: File berhasil disimpan di: $savedPath ---");

      // ✅ Langsung buka file setelah tersimpan
      if (savedPath != null) {
        await OpenFilex.open(savedPath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF berhasil disimpan: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("--- ERROR SAAT EKSPOR PDF: $e ---");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
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
                      // 1. Ganti SizedBox dengan Row untuk menampung dua tombol
                      child: Row(
                        children: [
                          // 2. Tombol Export Excel (gunakan Expanded agar lebarnya fleksibel)
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: _isProcessing
                                  ? Container(
                                      width: 20,
                                      height: 20,
                                      padding: const EdgeInsets.all(2.0),
                                      child: const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.grid_on), // Icon untuk Excel
                              label: Text(
                                _isProcessing ? 'MEMPROSES...' : 'Export Excel',
                              ),
                              onPressed: _isProcessing
                                  ? null
                                  : () => _exportToExcel(transactions),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor:
                                    _isProcessing ? Colors.grey : Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),

                          // 3. Tambahkan Spasi di antara tombol
                          const SizedBox(width: 16),

                          // 4. Tombol Export PDF BARU (gunakan Expanded juga)
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: _isProcessing
                                  ? Container(
                                      width: 20,
                                      height: 20,
                                      padding: const EdgeInsets.all(2.0),
                                      child: const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.picture_as_pdf), // Icon untuk PDF
                              label: Text(
                                _isProcessing ? 'MEMPROSES...' : 'Export PDF',
                              ),
                              onPressed: _isProcessing
                                  ? null
                                  : () => _exportToPdf(transactions),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: _isProcessing
                                    ? Colors.grey
                                    : Colors.red, // Warna merah untuk PDF
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
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
                                  Text(data['nama_transaction_method'] ?? ''),
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
