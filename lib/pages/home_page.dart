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

  // Form Controllers
  final _hargaBeliController = TextEditingController();
  final _hargaJualController = TextEditingController();

  // State Variables for Dropdowns
  PaymentMethod? _selectedPaymentMethod;
  Rekening? _selectedRekening;

  // State variable for loading indicator
  bool _isSubmitting = false;

  // Formatter for currency
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  // --- DATA FETCHING & SUBMISSION LOGIC ---

  // PERBAIKAN #3: Mengambil data dari sub-koleksi, bukan koleksi level atas
  Stream<QuerySnapshot> _getRekeningStream() {
    return _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('rekening')
        .snapshots();
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

  void _clearForm() {
    _hargaBeliController.clear();
    _hargaJualController.clear();
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
        _selectedPaymentMethod == null ||
        _selectedRekening == null ||
        _hargaBeliController.text.isEmpty ||
        _hargaJualController.text.isEmpty) {
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
      // Ambil nilai dari form
      final hargaBeli = int.parse(
        _hargaBeliController.text.replaceAll('.', ''),
      );
      final hargaJual = int.parse(
        _hargaJualController.text.replaceAll('.', ''),
      );
      final biayaAdmin = _selectedPaymentMethod!.fee;

      final uangBersih = (hargaJual - biayaAdmin) - hargaBeli;

      // Siapkan data untuk transaksi baru
      final transactionData = {
        'uid_user': _currentUser!.uid,
        'uid_rekening': _selectedRekening!.id,
        'nama_rekening': _selectedRekening!.name,
        'harga_beli': hargaBeli,
        'harga_jual_admin': hargaJual,
        'nama_payment_method': _selectedPaymentMethod!.name,
        'biaya_admin': biayaAdmin,
        'uang_bersih': uangBersih,
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

      // Operasi 2: Kurangi saldo rekening sebesar harga beli
      batch.update(rekeningRef, {
        'saldo': FieldValue.increment(-(hargaBeli + biayaAdmin)),
      });

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
    _hargaJualController.dispose();
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
        title: const Text('Kasir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  );
                }
                if (!snapshot.hasData || snapshot.hasError) {
                  return const Text(
                    'Selamat Datang 👋🏻',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  title: 'Cash',
                  stream: _getRekeningStream(),
                  valueField: 'saldo',
                  onTap: _showRekeningCrud,
                ),

                _buildInfoCard(
                  title: 'Saldo',
                  stream: _getTransactionsStream(),
                  valueField: 'uang_bersih',
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
                  hint: const Text('Pilih Metode Pembayaran'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
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
            const SizedBox(height: 16),

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

            const SizedBox(height: 16),
            // Input Harga Beli
            TextFormField(
              controller: _hargaBeliController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Harga Beli',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Input Harga Jual
            TextFormField(
              controller: _hargaJualController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Harga Jual Admin',
                border: OutlineInputBorder(),
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
                    color: Colors.blueGrey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            // Tombol Submit
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitTransaction,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'SUBMIT TRANSAKSI',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Navigasi ke halaman CRUD dengan mengirim UID
                  Navigator.pushNamed(
                    context,
                    '/payment-method',
                    arguments: _currentUser!.uid,
                  );
                },
                icon: const Icon(Icons.settings, size: 20),
                label: const Text('Atur Metode Pembayaran'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade200,
                  foregroundColor: Colors.black87,
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
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
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
