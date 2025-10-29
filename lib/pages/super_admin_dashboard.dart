import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_search/dropdown_search.dart';

// Assuming your files are in lib/app_routes.dart and lib/services/auth_service.dart
import '../app_routes.dart';
import '../services/auth_service.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _selectedRole = 'admin_agen';
  DocumentSnapshot? _selectedAdminAgen;

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔹 Async search for Admin Agen
  Future<List<DocumentSnapshot>> _searchAdminAgen(String filter) async {
    // Start with the base query
    Query query = _firestore
        .collection('users')
        .where('role', isEqualTo: 'admin_agen')
        .orderBy('email');

    // Only apply text filter if it's not empty
    if (filter.isNotEmpty) {
      query = query.startAt([filter]).endAt(['$filter\uf8ff']);
    }

    final snapshot = await query.limit(20).get();
    return snapshot.docs;
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == 'kasir' && _selectedAdminAgen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an Admin Agen first.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final String? error = await _authService.createUser(
      email: _emailController.text,
      password: _passwordController.text,
      role: _selectedRole,
      adminAgenId: _selectedRole == 'kasir' ? _selectedAdminAgen!.id : null,
    );

    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $error')));
      return;
    }

    _emailController.clear();
    _passwordController.clear();
    setState(() {
      _selectedRole = 'admin_agen';
      _selectedAdminAgen = null; // Clear the dropdown selection
    });

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created successfully!')));
  }

  @override
  Widget build(BuildContext context) {
    final dropdownWidth = MediaQuery.of(context).size.width - 32;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => await _authService.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create New User',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    // Role Dropdown
                    SizedBox(
                      width: dropdownWidth,
                      child: DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'admin_agen', child: Text('Admin Agen')),
                          DropdownMenuItem(
                              value: 'kasir', child: Text('Kasir')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedRole = value!;
                            _selectedAdminAgen = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Admin Agen dropdown with search (for Kasir)
                    if (_selectedRole == 'kasir')
                      SizedBox(
                        width: dropdownWidth,
                        child: DropdownSearch<DocumentSnapshot>(
                          // Clears selection when form resets
                          selectedItem: _selectedAdminAgen,

                          // Fix: Renamed from dropdownDecoratorProps
                          decoratorProps: DropDownDecoratorProps(
                            // Fix: Renamed from dropdownSearchDecoration
                            decoration: InputDecoration(
                              labelText: "Select Admin Agen",
                              hintText: "Search by email...",
                              prefixIcon: const Icon(Icons.person_search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),

                          // Fix: Renamed from asyncItems
                          items: (String filter, _) => _searchAdminAgen(filter),

                          itemAsString: (doc) {
                            // Safer data access
                            final data = doc?.data() as Map<String, dynamic>?;
                            return data?['email'] as String? ?? '';
                          },

                          // Fix: Added compareFn for custom type
                          compareFn: (item1, item2) => item1?.id == item2?.id,

                          onChanged: (value) {
                            setState(() {
                              _selectedAdminAgen = value;
                            });
                          },

                          // Fix: Returns empty string when null
                          dropdownBuilder: (context, selectedItem) {
                            final data =
                                selectedItem?.data() as Map<String, dynamic>?;
                            final email = data?['email'] as String?;
                            return Text(email ?? ""); // Fixes overlap
                          },

                          popupProps: PopupProps.menu(
                            showSearchBox: true,

                            title: const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Text(
                                "Select Admin Agen",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            searchFieldProps: TextFieldProps(
                              padding: const EdgeInsets.all(12),
                              decoration: InputDecoration(
                                hintText: "Search...",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),

                            // Fix: Correct signature with 4 params & safe access
                            itemBuilder:
                                (context, item, isSelected, isDisabled) {
                              final data =
                                  item?.data() as Map<String, dynamic>?;
                              final email =
                                  data?['email'] as String? ?? 'Invalid Data';

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                color: isDisabled ? Colors.grey[200] : null,
                                child: Text(
                                  email,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isDisabled ? Colors.grey[500] : null,
                                  ),
                                ),
                              );
                            },

                            // Fix: shape is inside menuProps
                            menuProps: MenuProps(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 10),

                    // Email & Password
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Enter email'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Enter password'
                          : null,
                    ),

                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _createUser,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Create User'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Navigation to Users List
          Card(
            child: ListTile(
              title: const Text('View All Users'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Navigator.pushNamed(context, AppRoutes.userList),
            ),
          ),
        ],
      ),
    );
  }
}
