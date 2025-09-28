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
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final int value = int.parse(newValue.text);
    final formatter = NumberFormat.decimalPattern('id_ID');
    final String newText = formatter.format(value);

    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
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

  String? _selectedTransactionMethod;

  Cash? _selectedCashAccount;

  Future<List<String>>? _combinedMethodsFuture;

  // Form Controllers
  final _hargaBeliController = TextEditingController();
  final _biayaAdminDalamController = TextEditingController();

  // State Variables for Dropdowns
  PaymentMethod? _selectedPaymentMethod;
  Rekening? _selectedRekening;

  // State variable for loading indicator
  bool _isSubmitting = false;

  Future<List<String>> _getCombinedTransactionMethods() async {
    if (_currentUser == null) return _staticTransactionMethods;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('transaction_methods')
          .get();

      final dynamicMethods = snapshot.docs
          .map((doc) => doc['metode_transaction'] as String)
          .toList();

      final combinedSet = {..._staticTransactionMethods, ...dynamicMethods};

      return combinedSet.toList();
    } catch (e) {
      print("Gagal mengambil metode transaksi dinamis: $e");

      return _staticTransactionMethods;
    }
  }

  // Formatter for currency
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  Stream<QuerySnapshot> _getRekeningStream() {
    return _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('rekening')
        .snapshots();
  }

  Stream<QuerySnapshot> _getCashStream() {
    if (_currentUser == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('cash')
        .snapshots();
  }

  void _showCashCrud() {
    if (_currentUser == null) return;
    showDialog(
      context: context,
      builder: (context) {
        return CashCrudDialog(userId: _currentUser!.uid);
      },
    );
  }

  Stream<QuerySnapshot> _getPaymentMethodsStream() {
    return _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('payment_methods')
        .snapshots();
  }

  Stream<QuerySnapshot> _getTransactionsStream() {
    return _firestore
        .collection('transactions')
        .where('uid_user', isEqualTo: _currentUser!.uid)
        .snapshots();
  }

  Stream<QuerySnapshot> _getTransactionMethodsStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('transaction_methods')
        .snapshots();
  }

  void _clearForm() {
    _hargaBeliController.clear();
    _biayaAdminDalamController.clear();
    setState(() {
      _selectedPaymentMethod = null;
      _selectedRekening = null;
    });
  }

  void _showRekeningCrud() {
    if (_currentUser == null) return;
    showDialog(
      context: context,
      builder: (context) {
        return RekeningCrudDialog(userId: _currentUser!.uid);
      },
    );
  }

  Future<void> _submitTransaction() async {
    if (_currentUser == null ||
        _selectedTransactionMethod == null ||
        _selectedPaymentMethod == null ||
        _selectedRekening == null ||
        (_selectedTransactionMethod == 'Tarik Tunai' &&
            _selectedCashAccount == null) ||
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
        _hargaBeliController.text.replaceAll('.', ''),
      );
      final biayaAdminDalam = int.parse(
        _biayaAdminDalamController.text.replaceAll('.', ''),
      );
      final biayaAdmin = _selectedPaymentMethod!.fee;

      final uangBersih = (hargaBeli + biayaAdminDalam) - biayaAdmin;

      final uangProfit = biayaAdminDalam - biayaAdmin;

      final uangKotor = hargaBeli + biayaAdminDalam;

      // Siapkan data untuk transaksi baru
      final transactionData = {
        'uid_user': _currentUser!.uid,
        'uid_rekening': _selectedRekening!.id,
        'nama_rekening': _selectedRekening!.name,
        'uid_cash': _selectedCashAccount?.id,
        'nama_cash': _selectedCashAccount?.name,
        'nama_transaction_method': _selectedTransactionMethod,
        'harga_beli': hargaBeli,
        'harga_jual_admin': biayaAdminDalam,
        'nama_payment_method': _selectedPaymentMethod!.name,
        'biaya_admin': biayaAdmin,
        'uang_profit': uangProfit,
        'uang_bersih': uangBersih,
        'uang_kotor': uangKotor,
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Referensi ke dokumen rekening yang akan diupdate
      final rekeningRef = _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('rekening')
          .doc(_selectedRekening!.id);

      WriteBatch batch = _firestore.batch();

      batch.set(_firestore.collection('transactions').doc(), transactionData);

      if (_selectedTransactionMethod == 'Tarik Tunai') {
        print("DEBUG: Menjalankan logika Tarik Tunai");

        final rekeningRef = _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('rekening')
            .doc(_selectedRekening!.id);
        final cashRef = _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('cash')
            .doc(_selectedCashAccount!.id);

        // Saldo Kas Tunai berkurang sebesar jumlah yang diambil pelanggan
        batch.update(cashRef, {'saldo': FieldValue.increment(-hargaBeli)});

        // Saldo Rekening bertambah sebesar profit
        batch.update(rekeningRef, {'saldo': FieldValue.increment(uangBersih)});
      } else {
        // Skenario 2: Metode Lain (misal: Setor Tunai, Transfer)
        print("DEBUG: Menjalankan logika Setor Tunai/Transfer");

        // Referensi ke rekening (sumber dana digital) dan kas (tujuan profit)
        final rekeningRef = _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('rekening')
            .doc(_selectedRekening!.id);
        final cashRef = _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('cash')
            .doc(_selectedCashAccount!.id);

        // Saldo Rekening berkurang sebesar total pengeluaran
        batch.update(rekeningRef,
            {'saldo': FieldValue.increment(-(hargaBeli + biayaAdminDalam))});

        // Saldo Kas Tunai bertambah sebesar profit
        batch.update(cashRef, {'saldo': FieldValue.increment(uangBersih)});
      }

      // Jalankan kedua operasi
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaksi berhasil disimpan!'),
          backgroundColor: Colors.green,
        ),
      );

      _clearForm();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan transaksi: $e'),
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
  void initState() {
    super.initState();
    _selectedTransactionMethod = _staticTransactionMethods[0];
    _combinedMethodsFuture = _getCombinedTransactionMethods();
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
                final userData = userDoc.data() as Map<String, dynamic>;

                print("--- DEBUG DATA PENGGUNA DARI FIRESTORE ---");
                print(userData);
                print("------------------------------------------");

                final userName = userData['name'] ?? 'Pengguna';

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
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/laporan',
                        arguments: _currentUser!.uid,
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

                final List<String> methodsList =
                    snapshot.hasData && snapshot.data!.isNotEmpty
                        ? snapshot.data!
                        : _staticTransactionMethods;

                return DropdownButtonFormField<String>(
                  value: _selectedTransactionMethod,
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
                    // _checkFormCompletion();
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
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                var paymentMethods = snapshot.data!.docs
                    .map((doc) => PaymentMethod.fromFirestore(doc))
                    .toList();

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
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                var rekeningList = snapshot.data!.docs
                    .map((doc) => Rekening.fromFirestore(doc))
                    .toList();
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
                  onChanged: (Rekening? newValue) =>
                      setState(() => _selectedRekening = newValue),
                  validator: (value) => value == null ? 'Wajib diisi' : null,
                );
              },
            ),
            const SizedBox(height: 8),

            // Dropdown Rekening Cash (Hanya tampil jika metode transaksi adalah "Tarik Tunai")
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(_currentUser!.uid)
                  .collection('cash')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                if (snapshot.data!.docs.isEmpty) {
                  return const Text('Anda belum memiliki akun kas tunai.',
                      style: TextStyle(color: Colors.red));
                }

                final cashList = snapshot.data!.docs
                    .map((doc) => Cash.fromFirestore(doc))
                    .toList();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: DropdownButtonFormField<Cash>(
                    value: _selectedCashAccount,
                    hint: const Text('Pilih Rekening Cash'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.wallet_giftcard),
                    ),
                    items: cashList.map((cash) {
                      return DropdownMenuItem(
                          value: cash, child: Text(cash.name));
                    }).toList(),
                    onChanged: (Cash? newValue) {
                      setState(() {
                        _selectedCashAccount = newValue;
                      });
                      // _checkFormCompletion();
                    },
                    validator: (value) => value == null
                        ? 'Rekening tujuan profit wajib diisi'
                        : null,
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
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'SUBMIT TRANSAKSI',
                        style: TextStyle(
                          color: Colors.white,
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
                  style: TextStyle(
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
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    if (!snapshot.hasData) return const Text('Error');

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
