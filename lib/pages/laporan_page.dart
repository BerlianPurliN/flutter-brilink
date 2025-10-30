import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum FilterType { none, byMethod, byDateRange }

class LaporanPage extends StatefulWidget {
  final String? userId; // Ini akan menerima _adminAgenId dari navigasi
  const LaporanPage({super.key, this.userId});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _currencyFormatter = NumberFormat.decimalPattern('id_ID');
  bool _isProcessing = false;
  String? _selectedFilterMethod;
  String? _adminAgenId; // Mengganti nama _userId
  String? _userRole;

  FilterType _activeFilter = FilterType.none;
  String? _selectedMethod; // Untuk filter berdasarkan metode
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _adminAgenId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        setState(() {
          _userRole = userDoc.data()?['role'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error loading user role: $e');
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
              'Rp ${_currencyFormatter.format((data['biaya_admin_fee'] as num?)?.toInt() ?? 0)}'), // Ganti nama field
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
      await OpenFilex.open(savedPath);

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
    final currentUser = FirebaseAuth.instance.currentUser;

    // ✅ Log: check user first
    if (currentUser == null) {
      print('❌ No user logged in.');
      return;
    }
    print('👤 Current user UID: ${currentUser.uid}');
    print('📡 Fetching transactions for this user...');

    try {
      final snapshot = await _firestore
          .collection('transactions')
          .where('uid_user', isEqualTo: currentUser.uid)
          .get();

      print('✅ Query executed successfully.');
      print('📊 Transaction count: ${snapshot.docs.length}');

      // Log first few docs to verify fields
      for (var i = 0; i < snapshot.docs.length && i < 3; i++) {
        final data = snapshot.docs[i].data();
        print('🧾 Doc #$i: ${data}');
      }

      final availableMethods = [
        ...snapshot.docs
            .map((doc) => (doc.data())['nama_payment_method'] as String?)
            .where((item) => item != null)
            .toSet(),
      ];

      availableMethods.sort();

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
                    title: Text(method ?? 'Metode Tidak Dikenal'),
                    onTap: () {
                      setState(() {
                        _activeFilter = FilterType.byMethod;
                        _selectedMethod = method;
                        _selectedDateRange = null;
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
    } on FirebaseException catch (e) {
      print('🔥 FIREBASE EXCEPTION ---');
      print('Code: ${e.code}');
      print('Message: ${e.message}');
      print('Stack trace: ${e.stackTrace}');
      print('--------------------------');
    } catch (e, stack) {
      print('❌ UNKNOWN ERROR: $e');
      print(stack);
    }
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

  // Fungsi ini sepertinya tidak terpakai, bisa dihapus
  // void _showFilterDialog(List<String> availableMethods) { ... }

  // ✅ DIPERBAIKI: Menggunakan _adminAgenId
  Future<void> _deleteTransaction(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;

    // Ambil data yang relevan dari transaksi
    final hargaBeli = (data['harga_beli'] as num?)?.toInt() ?? 0;
    final uangBersih = (data['uang_bersih'] as num?)?.toInt() ?? 0;
    final uangKotor = (data['uang_kotor'] as num?)?.toInt() ?? 0;
    final transactionMethod = data['nama_transaction_method'] as String?;

    final rekeningId = data['uid_rekening'] as String?;
    final cashId = data['uid_cash'] as String?;

    if (rekeningId == null || cashId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: ID rekening/kas hilang di transaksi.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: const Text(
          'Anda yakin ingin menghapus transaksi ini? Saldo akan dikembalikan.',
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
            .doc(_adminAgenId) // ✅ DIGANTI
            .collection('rekening')
            .doc(rekeningId);

        final cashRef = _firestore
            .collection('users')
            .doc(_adminAgenId) // ✅ DIGANTI
            .collection('cash')
            .doc(cashId);

        WriteBatch batch = _firestore.batch();

        // Logika pembalikan saldo
        if (transactionMethod == 'Tarik Tunai') {
          // Kembalikan uang ke Kas Tunai
          batch.update(cashRef, {'saldo': FieldValue.increment(hargaBeli)});
          // Kurangi uang dari Rekening
          batch.update(
              rekeningRef, {'saldo': FieldValue.increment(-uangBersih)});
        } else {
          // Skenario 2: Metode Lain (misal: Setor Tunai, Transfer) saat DELETE
          print("DEBUG: Membalikkan logika Setor Tunai/Transfer");

          // Kembalikan uang ke Rekening (Jumlah + Fee)
          final int fee = (data['biaya_admin_fee'] as num?)?.toInt() ?? 0;
          // Pastikan hargaBeli adalah non-nullable int
          final int hargaBeliInt = (data['harga_beli'] as num?)?.toInt() ?? 0;
          final int totalPengeluaranRekening = hargaBeliInt + fee;
          batch.update(rekeningRef,
              {'saldo': FieldValue.increment(totalPengeluaranRekening)});

          // Kurangi uang dari Kas Tunai (Jumlah + Biaya Admin Pelanggan)
          final int hargaJualAdmin =
              (data['harga_jual_admin'] as num?)?.toInt() ?? 0;
          final int uangKotorToDelete =
              hargaBeliInt + hargaJualAdmin; // Hitung uangKotor di sini
          batch.update(
              cashRef, {'saldo': FieldValue.increment(-uangKotorToDelete)});
        }

        // Hapus dokumen transaksi
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

  // ✅ DIPERBAIKI: Menggunakan _adminAgenId
  void _showEditTransactionDialog(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final hargaBeliController = TextEditingController(
      text: data['harga_beli'].toString(),
    );
    final hargaJualController = TextEditingController(
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
                controller: hargaBeliController,
                decoration: const InputDecoration(labelText: 'Harga Beli'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ], // Perlu Currency Formatter
              ),
              TextField(
                controller: hargaJualController,
                decoration: const InputDecoration(
                  labelText: 'Biaya Admin Dalam',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ], // Perlu Currency Formatter
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
                final int oldHargaBeli =
                    (data['harga_beli'] as num?)?.toInt() ?? 0;

                final int? newHargaBeli = int.tryParse(
                  hargaBeliController.text
                      .replaceAll(RegExp(r'[^\d]'), ''), // Hapus format
                );
                final int? newHargaJual = int.tryParse(
                  hargaJualController.text
                      .replaceAll(RegExp(r'[^\d]'), ''), // Hapus format
                );

                // ✅ Blok if untuk null safety
                if (newHargaBeli != null && newHargaJual != null) {
                  // --- PINDAHKAN SEMUA PERHITUNGAN KE SINI ---
                  final int biayaAdminFee =
                      (data['biaya_admin_fee'] as num?)?.toInt() ?? 0;
                  final String transactionMethod =
                      data['nama_transaction_method'];

                  final int newUangProfit = newHargaJual - biayaAdminFee;
                  final int newUangKotor = newHargaBeli + newHargaJual;
                  final int newUangBersih = newHargaBeli + newUangProfit;

                  // Perhitungan delta sekarang aman karena new... bukan null
                  final int deltaHargaBeli = newHargaBeli - oldHargaBeli;
                  final int deltaUangBersih = newUangBersih -
                      ((data['uang_bersih'] as num?)?.toInt() ?? 0);
                  final int deltaUangKotor = newUangKotor -
                      ((data['uang_kotor'] as num?)?.toInt() ?? 0);
                  // --- AKHIR DARI PERHITUNGAN ---

                  try {
                    final rekeningId = data['uid_rekening'] as String?;
                    final cashId = data['uid_cash'] as String?;
                    if (rekeningId == null || cashId == null) {
                      throw Exception("ID rekening atau kas hilang");
                    }

                    final rekeningRef = _firestore
                        .collection('users')
                        .doc(_adminAgenId)
                        .collection('rekening')
                        .doc(rekeningId);

                    final cashRef = _firestore
                        .collection('users')
                        .doc(_adminAgenId)
                        .collection('cash')
                        .doc(cashId);

                    WriteBatch batch = _firestore.batch();

                    // Operasi 1: Update transaksi
                    batch.update(doc.reference, {
                      'harga_beli': newHargaBeli,
                      'harga_jual_admin': newHargaJual,
                      'uang_profit': newUangProfit,
                      'uang_kotor': newUangKotor,
                      'uang_bersih': newUangBersih,
                    });

                    // Operasi 2: Sesuaikan saldo
                    if (transactionMethod == 'Tarik Tunai') {
                      batch.update(cashRef,
                          {'saldo': FieldValue.increment(-deltaHargaBeli)});
                      batch.update(rekeningRef,
                          {'saldo': FieldValue.increment(deltaUangBersih)});
                    } else {
                      batch.update(rekeningRef,
                          {'saldo': FieldValue.increment(-deltaHargaBeli)});
                      batch.update(cashRef,
                          {'saldo': FieldValue.increment(deltaUangKotor)});
                    }

                    await batch.commit();

                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal update: $e')),
                      );
                    }
                  }
                } else {
                  // Jika input tidak valid (bukan angka)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Input tidak valid. Harap masukkan angka.')),
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
                  'Rp ${_currencyFormatter.format(data['biaya_admin_fee'] ?? 0)}', // Ganti nama field
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
            'Rp ${_currencyFormatter.format(d['biaya_admin_fee'] ?? 0)}'; // Ganti nama field
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
      await OpenFilex.open(savedPath);

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
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Center(child: Text('User tidak terautentikasi'));
    }

    // 🧩 TUNGGU hingga role selesai dimuat
    if (_userRole == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // ✅ Gunakan StreamBuilder hanya setelah role dimuat
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: (() {
          Query<Map<String, dynamic>> query =
              _firestore.collection('transactions');

          // 🧩 Tentukan query sesuai role
          if (_userRole == 'kasir') {
            query = query.where('uid_user', isEqualTo: currentUser.uid);
          } else if (_userRole == 'admin_agen') {
            query = query.where('uid_admin_agen', isEqualTo: currentUser.uid);
          }

          // 🧭 Tambahkan filter jika ada
          if (_selectedMethod != null && _selectedMethod!.isNotEmpty) {
            query =
                query.where('nama_payment_method', isEqualTo: _selectedMethod);
          }

          if (_selectedDateRange != null) {
            final start = DateTime(
              _selectedDateRange!.start.year,
              _selectedDateRange!.start.month,
              _selectedDateRange!.start.day,
            );
            final end = DateTime(
              _selectedDateRange!.end.year,
              _selectedDateRange!.end.month,
              _selectedDateRange!.end.day,
              23,
              59,
              59,
            );

            query = query
                .where('timestamp', isGreaterThanOrEqualTo: start)
                .where('timestamp', isLessThanOrEqualTo: end);
          }

          debugPrint('🔥 Query for role: $_userRole');
          debugPrint('🪪 Using UID: ${currentUser.uid}');

          return query.orderBy('timestamp', descending: true).snapshots();
        })(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint('🔥 FIRESTORE ERROR: ${snapshot.error}');
            return Center(child: Text('Gagal memuat data: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
                child: Text('Tidak ada transaksi yang cocok dengan filter.'));
          }

          final transactions = snapshot.data!.docs;

          return Column(
            children: [
              // 🔽 Tombol export
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(Icons.grid_on),
                        label: Text(
                            _isProcessing ? 'MEMPROSES...' : 'Export Excel'),
                        onPressed: _isProcessing
                            ? null
                            : () => _exportToExcel(transactions),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label:
                            Text(_isProcessing ? 'MEMPROSES...' : 'Export PDF'),
                        onPressed: _isProcessing
                            ? null
                            : () => _exportToPdf(transactions),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🔽 Daftar transaksi
              Expanded(
                child: ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final doc = transactions[index];
                    final data = doc.data();
                    final timestamp =
                        (data['timestamp'] as Timestamp?)?.toDate();
                    final formattedDate = timestamp != null
                        ? DateFormat('dd/MM/yyyy HH:mm').format(timestamp)
                        : 'N/A';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(
                          data['nama_payment_method'] ?? 'Metode Tidak Dikenal',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tanggal: $formattedDate'),
                            Text('Rekening: ${data['nama_rekening'] ?? '-'}'),
                            Text(
                              'Profit: Rp ${_currencyFormatter.format(data['uang_profit'] ?? 0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'detail') {
                              _showTransactionDetailDialog(doc);
                            } else if (value == 'edit') {
                              _showEditTransactionDialog(doc);
                            } else if (value == 'delete') {
                              _deleteTransaction(doc);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'detail',
                              child: Text('Lihat Detail'),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Hapus',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
