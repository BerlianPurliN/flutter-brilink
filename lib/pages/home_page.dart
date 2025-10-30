import 'package:brilink/pages/cash_crud_dialog.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:brilink/services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brilink/widgets/rekening_crud.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// --- MODEL CLASS ---

class PaymentMethod extends Equatable {
  final String id;
  final String name;
  final int fee;

  const PaymentMethod({
    required this.id,
    required this.name,
    required this.fee,
  });

  factory PaymentMethod.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return PaymentMethod(
      id: doc.id,
      name: data['nama_payment'] ?? '',
      fee: (data['fee'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [id];
}

class Rekening extends Equatable {
  final String id;
  final String name;
  final int balance;

  const Rekening({required this.id, required this.name, required this.balance});

  factory Rekening.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Rekening(
      id: doc.id,
      name: data['nama_rekening'] ?? '',
      balance: (data['saldo'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [id];
}

class Cash extends Equatable {
  final String id;
  final String name;
  final int balance;

  const Cash({
    required this.id,
    required this.name,
    required this.balance,
  });

  factory Cash.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return Cash(
      id: doc.id,
      name: data['nama_kas'] ?? '',
      balance: (data['saldo'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [id];
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }

    try {
      final int value = int.parse(digitsOnly);
      final formatter = NumberFormat.decimalPattern('id_ID');
      final String newText = formatter.format(value);

      return newValue.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    } catch (e) {
      return oldValue;
    }
  }
}

class TransactionMethod extends Equatable {
  final String id;
  final String name;

  const TransactionMethod({required this.id, required this.name});

  factory TransactionMethod.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TransactionMethod(
      id: doc.id,
      name: data['metode_transaction'] ?? 'Tanpa Nama',
    );
  }
  @override
  List<Object?> get props => [id, name];
}

// --- ENUM BARU UNTUK JENIS BIAYA ADMIN ---
enum AdminFeeType {
  normal,
  externalFee, // Biaya Admin Luar (diinput Kasir)
  atmSelf, // Biaya ATM Sendiri
}

// --- HOME PAGE WIDGET ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Instance Services
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final List<String> _staticTransactionMethods = [
    'Tarik Tunai',
  ];

  // State Variables
  String? _selectedTransactionMethod;
  Cash? _selectedCashAccount;
  PaymentMethod? _selectedPaymentMethod;
  Rekening? _selectedRekening;
  Future<List<String>>? _combinedMethodsFuture;
  bool _isSubmitting = false;

  // --- VARIABEL LOGIKA ROLE & DATA ---
  String? _adminAgenId;
  String? _kasirName;
  bool _isLoadingData = true;
  bool _isAdminAgen = false;

  // --- Form Controllers ---
  final _hargaBeliController = TextEditingController();
  final _biayaAdminDalamController = TextEditingController();

  // --- VARIABEL FEE BARU ---
  AdminFeeType _selectedAdminFeeType = AdminFeeType.normal;
  final _biayaAdminLuarController = TextEditingController();

  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _selectedTransactionMethod = _staticTransactionMethods[0];
    _combinedMethodsFuture = _getCombinedTransactionMethods();
    _fetchUserData(); // Panggil fungsi untuk mengambil ID Admin Agen
  }

  // ✅ FUNGSI BARU: Mengambil data user untuk mendapatkan managed_by
  Future<void> _fetchUserData() async {
    if (_currentUser == null) return;
    try {
      final userDoc =
          await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _kasirName = data['name'] ?? data['email'];
          _adminAgenId = data['managed_by']; // Simpan ID Admin Agen
        });
      }
    } catch (e) {
      print("Gagal mengambil data user: $e");
    }
  }

  Future<List<String>> _getCombinedTransactionMethods() async {
    if (_adminAgenId == null)
      return _staticTransactionMethods; // Gunakan Admin ID

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_adminAgenId!) // 👈 Gunakan Admin ID
          .collection('transaction_methods')
          .get();

      final dynamicMethods = snapshot.docs
          .map((doc) => doc.data()['metode_transaction'] as String)
          .toList();

      final combinedSet = {..._staticTransactionMethods, ...dynamicMethods};
      return combinedSet.toList();
    } catch (e) {
      print("Gagal mengambil metode transaksi dinamis: $e");
      return _staticTransactionMethods;
    }
  }

  Stream<QuerySnapshot> _getRekeningStream() {
    if (_currentUser == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_currentUser!.uid) // ✅ HARUS PAKAI _currentUser!.uid
        .collection('rekening')
        .snapshots();
  }

  Stream<QuerySnapshot> _getCashStream() {
    if (_currentUser == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_currentUser!.uid) // ✅ HARUS PAKAI _currentUser!.uid
        .collection('cash')
        .snapshots();
  }

  void _showCashCrud() {
    if (_adminAgenId == null) return; // Gunakan Admin ID
    showDialog(
      context: context,
      builder: (context) {
        return CashCrudDialog(userId: _adminAgenId!); // 👈 DIGANTI
      },
    );
  }

  Stream<QuerySnapshot> _getPaymentMethodsStream() {
    if (_currentUser == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_currentUser!.uid) // ✅ HARUS PAKAI _currentUser!.uid
        .collection('payment_methods')
        .snapshots();
  }

  Stream<QuerySnapshot> _getTransactionsStream() {
    // Transaksi tetap milik Kasir (uid_user)
    if (_currentUser == null) return const Stream.empty();
    return _firestore
        .collection('transactions')
        .where('uid_user', isEqualTo: _currentUser!.uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  void _clearForm() {
    _hargaBeliController.clear();
    _biayaAdminDalamController.clear();
    setState(() {
      _selectedPaymentMethod = null;
      _selectedRekening = null;
      _selectedCashAccount = null;
    });
  }

  void _showRekeningCrud() {
    if (_adminAgenId == null) return; // Gunakan Admin ID
    showDialog(
      context: context,
      builder: (context) {
        return RekeningCrudDialog(userId: _adminAgenId!); // 👈 DIGANTI
      },
    );
  }

  Future<void> _submitTransaction() async {
    if (_currentUser == null ||
        _adminAgenId == null || // Added check for Admin ID
        _selectedTransactionMethod == null ||
        _selectedPaymentMethod == null ||
        _selectedRekening == null ||
        _selectedCashAccount == null ||
        _hargaBeliController.text.isEmpty ||
        _biayaAdminDalamController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap lengkapi semua field.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final hargaBeli = int.parse(
        _hargaBeliController.text.replaceAll(RegExp(r'[^\d]'), ''),
      );
      final biayaAdminDalam = int.parse(
        _biayaAdminDalamController.text.replaceAll(RegExp(r'[^\d]'), ''),
      );
      final biayaAdmin = _selectedPaymentMethod!.fee;

      final uangBersih = (hargaBeli + biayaAdminDalam) - biayaAdmin;
      final uangProfit = biayaAdminDalam - biayaAdmin;
      final uangKotor = hargaBeli + biayaAdminDalam;

      // Data for the new transaction document
      final transactionData = {
        'uid_user': _currentUser!.uid,
        'uid_admin_agen': _adminAgenId, // ✅ Storing Admin ID
        'uid_rekening': _selectedRekening!.id,
        'nama_rekening': _selectedRekening!.name,
        'uid_cash': _selectedCashAccount!.id,
        'nama_cash': _selectedCashAccount!.name,
        'nama_transaction_method': _selectedTransactionMethod,
        'harga_beli': hargaBeli,
        'harga_jual_admin': biayaAdminDalam,
        'nama_payment_method': _selectedPaymentMethod!.name,
        'biaya_admin_fee': biayaAdmin,
        'uang_profit': uangProfit,
        'uang_bersih': uangBersih,
        'uang_kotor': uangKotor,
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Use Sequential Write (No Batch)
      final newTransactionRef = _firestore.collection('transactions').doc();
      print("Attempting to set transaction at path: ${newTransactionRef.path}");
      await newTransactionRef.set(transactionData);
      print("Transaction set successfully.");

      // References use _adminAgenId
      final rekeningRef = _firestore
          .collection('users')
          .doc(_adminAgenId!) // 👈 DIGANTI
          .collection('rekening')
          .doc(_selectedRekening!.id);
      final cashRef = _firestore
          .collection('users')
          .doc(_adminAgenId!) // 👈 DIGANTI
          .collection('cash')
          .doc(_selectedCashAccount!.id);

      if (_selectedTransactionMethod == 'Tarik Tunai') {
        print("DEBUG: Menjalankan logika Tarik Tunai (Sequential)");
        print("Attempting to update cash at path: ${cashRef.path}");
        await cashRef.update({'saldo': FieldValue.increment(-hargaBeli)});

        print("Attempting to update rekening at path: ${rekeningRef.path}");
        await rekeningRef.update({'saldo': FieldValue.increment(uangBersih)});
      } else {
        // Skenario 2: Metode Lain (misal: Setor Tunai, Transfer)
        print("DEBUG: Menjalankan logika Setor Tunai/Transfer (Sequential)");

        // ✅ PERBAIKAN LOGIKA FEE
        final int totalPengeluaranRekening = hargaBeli + biayaAdmin;

        print("Attempting to update rekening at path: ${rekeningRef.path}");
        await rekeningRef
            .update({'saldo': FieldValue.increment(-totalPengeluaranRekening)});

        print("Attempting to update cash at path: ${cashRef.path}");
        await cashRef.update({'saldo': FieldValue.increment(uangKotor)});
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaksi berhasil disimpan!'),
          backgroundColor: Colors.green,
        ),
      );

      _clearForm();
    } catch (e) {
      print("ERROR _submitTransaction (Sequential): $e");
      String errorMessage = 'Gagal menyimpan transaksi: $e';
      if (e is FirebaseException) {
        errorMessage = 'Gagal menyimpan transaksi: ${e.message ?? e.code}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _hargaBeliController.dispose();
    _biayaAdminDalamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("User tidak ditemukan, silakan login ulang.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Kasir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await _authService.signOut();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<QuerySnapshot>(
              future: _firestore
                  .collection('users')
                  .where('uid', isEqualTo: _currentUser!.uid)
                  .limit(1)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Text(
                    'Memuat...',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  );
                }
                if (!snapshot.hasData || snapshot.hasError) {
                  return const Text(
                    'Selamat Datang 👋🏻',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  );
                }

                // Jika data berhasil diambil, tampilkan nama pengguna
                final userDoc = snapshot.data!.docs.first;
                final data = userDoc.data() as Map<String, dynamic>;

                print("--- DEBUG DATA USER: ${data['role']} ---");

                // ✅ Simpan Admin ID dan nama di state
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _adminAgenId = data['managed_by']; // Simpan ID Admin Agen
                      _kasirName = data['name'] ?? data['email'];
                    });
                  }
                });

                final userName = data['name'] ?? 'Pengguna';

                return Text(
                  'Selamat Datang, $userName 👋🏻',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard(
                  title: 'Total Saldo',
                  stream: _getRekeningStream(),
                  valueField: 'saldo',
                  onTap: _showRekeningCrud,
                ),
                _buildInfoCard(
                  title: 'Total Cash',
                  valueField: 'saldo',
                  stream: _getCashStream(),
                  onTap: _showCashCrud,
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.18,
                  height: MediaQuery.of(context).size.width * 0.18,
                  child: ElevatedButton(
// KODE BARU:
                    onPressed: () {
                      // Pastikan Admin Agen ID ada sebelum navigasi
                      if (_adminAgenId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'ID Admin Agen belum dimuat atau tidak terhubung.')),
                        );
                        return;
                      }
                      Navigator.pushNamed(
                        context,
                        '/laporan',
                        arguments: _currentUser!
                            .uid, // ✅ Mengirim ID Admin Agen yang Benar
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(8),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Lihat Laporan',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                "Transaksi Baru",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            const SizedBox(height: 16),

            // --- BAGIAN FORM ---

            // Dropdown Metode Transaksi
            FutureBuilder<List<String>>(
              future: _combinedMethodsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Text('Metode transaksi belum diatur.');
                }

                final List<String> methodsList = snapshot.data!;

                // Pastikan nilai yang dipilih ada di daftar
                String? currentSelection = _selectedTransactionMethod;
                if (!methodsList.contains(currentSelection)) {
                  currentSelection =
                      methodsList.isNotEmpty ? methodsList[0] : null;
                  // Set state setelah build selesai untuk menghindari error
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted &&
                        _selectedTransactionMethod != currentSelection) {
                      setState(() {
                        _selectedTransactionMethod = currentSelection;
                      });
                    }
                  });
                }

                return DropdownButtonFormField<String>(
                  value: currentSelection,
                  hint: const Text('Metode Transaksi'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.swap_horiz),
                  ),
                  items: methodsList.map((String method) {
                    return DropdownMenuItem<String>(
                      value: method,
                      child: Text(method),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedTransactionMethod = newValue;
                    });
                  },
                  validator: (value) =>
                      value == null ? 'Metode transaksi wajib diisi' : null,
                );
              },
            ),
            const SizedBox(height: 8),

            // Dropdown Metode Pembayaran
            StreamBuilder<QuerySnapshot>(
              stream: _getPaymentMethodsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('Tujuan Pembayaran belum diatur.');
                }

                var paymentMethods = snapshot.data!.docs
                    .map((doc) => PaymentMethod.fromFirestore(doc))
                    .toList();

                if (_selectedPaymentMethod != null &&
                    !paymentMethods.contains(_selectedPaymentMethod)) {
                  _selectedPaymentMethod = null;
                }

                return DropdownButtonFormField<PaymentMethod>(
                  value: _selectedPaymentMethod,
                  hint: const Text('Tujuan Pembayaran'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: paymentMethods.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Text(method.name),
                    );
                  }).toList(),
                  onChanged: (PaymentMethod? newValue) =>
                      setState(() => _selectedPaymentMethod = newValue),
                  validator: (value) => value == null ? 'Wajib diisi' : null,
                );
              },
            ),
            const SizedBox(height: 8),

            // Dropdown Rekening
            StreamBuilder<QuerySnapshot>(
              stream: _getRekeningStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('Sumber Dana (Rekening) belum diatur.');
                }
                var rekeningList = snapshot.data!.docs
                    .map((doc) => Rekening.fromFirestore(doc))
                    .toList();

                if (_selectedRekening != null &&
                    !rekeningList.contains(_selectedRekening)) {
                  _selectedRekening = null;
                }

                return DropdownButtonFormField<Rekening>(
                  value: _selectedRekening,
                  hint: const Text('Sumber Dana (Rekening)'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_balance_wallet),
                  ),
                  items: rekeningList.map((rekening) {
                    return DropdownMenuItem(
                      value: rekening,
                      child: Text(rekening.name),
                    );
                  }).toList(),
                  onChanged: (Rekening? newValue) {
                    print(
                        "Rekening dipilih: ${newValue?.name}, ID: ${newValue?.id}");
                    setState(() => _selectedRekening = newValue);
                  },
                  validator: (value) => value == null ? 'Wajib diisi' : null,
                );
              },
            ),
            const SizedBox(height: 8),

            // Dropdown Rekening Cash (Hanya tampil jika metode transaksi adalah "Tarik Tunai")
            StreamBuilder<QuerySnapshot>(
              stream: _getCashStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: LinearProgressIndicator(),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('Akun kas tunai belum diatur.',
                      style: TextStyle(color: Colors.red));
                }

                final cashList = snapshot.data!.docs
                    .map((doc) => Cash.fromFirestore(doc))
                    .toList();

                if (_selectedCashAccount != null &&
                    !cashList.contains(_selectedCashAccount)) {
                  _selectedCashAccount = null;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: DropdownButtonFormField<Cash>(
                    value: _selectedCashAccount,
                    hint: const Text('Pilih Kas Tunai'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.wallet_giftcard),
                    ),
                    items: cashList.map((cash) {
                      return DropdownMenuItem(
                          value: cash, child: Text(cash.name));
                    }).toList(),
                    onChanged: (Cash? newValue) {
                      print(
                          "Cash dipilih: ${newValue?.name}, ID: ${newValue?.id}");
                      setState(() {
                        _selectedCashAccount = newValue;
                      });
                    },
                    validator: (value) =>
                        value == null ? 'Kas tunai wajib diisi' : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            // Input Nominal Transaksi
            TextFormField(
              controller: _hargaBeliController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CurrencyInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Jumlah Transaksi',
                border: OutlineInputBorder(),
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 8),
            // Input Harga Jual
            TextFormField(
              controller: _biayaAdminDalamController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CurrencyInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Biaya Admin',
                border: OutlineInputBorder(),
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 8),

            // Tampilan Biaya Admin
            if (_selectedPaymentMethod != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Biaya Admin: ${_currencyFormatter.format(_selectedPaymentMethod!.fee)}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // Tombol Submit
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade400,
                  foregroundColor: Colors.white,
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'SUBMIT TRANSAKSI',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/transaction-method',
                    arguments: _currentUser!.uid,
                  );
                },
                icon: const Icon(Icons.settings, size: 20),
                label: const Text('Atur Metode Transaksi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade400,
                  foregroundColor: Colors.white,
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/payment-method',
                    arguments: _currentUser!.uid,
                  );
                },
                icon: const Icon(Icons.settings, size: 20),
                label: const Text('Atur Tujuan Pembayaran'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade400,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required Stream<QuerySnapshot> stream,
    required String valueField,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Card(
          color: Colors.blue.shade400,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot>(
                  stream: stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 15,
                        width: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      );
                    }
                    if (!snapshot.hasData || snapshot.hasError) {
                      return const Text(
                        'Rp 0',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }

                    int totalValue = 0;
                    for (var doc in snapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      totalValue += (data[valueField] as num?)?.toInt() ?? 0;
                    }

                    return Text(
                      _currencyFormatter.format(totalValue),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
