import 'package:brilink/services/auth_service.dart';
import 'package:brilink/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateUserPage extends StatefulWidget {
  const CreateUserPage({super.key});

  @override
  State<CreateUserPage> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUserPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _selectedRole;
  bool _isLoading = false;

  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  String? _currentUserRole;

  List<String> _getAvailableRoles() {
    if (_currentUserRole == 'super_admin') {
      return ['admin_agen'];
    } else if (_currentUserRole == 'admin_agen') {
      return ['kasir'];
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserRole();
  }

  Future<void> _fetchCurrentUserRole() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .get();
    setState(() {
      _currentUserRole = userDoc.data()?['role'];
    });
  }

  Future<void> _createUser() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // This is a placeholder for the actual creation logic which will be implemented in the services
        // For now, we'll just show a success message
        print('Email: ${_emailController.text}');
        print('Password: ${_passwordController.text}');
        print('Role: $_selectedRole');

        // Simulate network call
        await Future.delayed(const Duration(seconds: 2));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User created successfully! (Placeholder)')),
        );
        Navigator.of(context).pop();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create user: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableRoles = _getAvailableRoles();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New User'),
      ),
      body: _currentUserRole == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter an email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    if (availableRoles.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRole,
                        hint: const Text('Select Role'),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedRole = newValue;
                          });
                        },
                        items: availableRoles
                            .map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        validator: (value) =>
                            value == null ? 'Please select a role' : null,
                      ),
                    const SizedBox(height: 32),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _createUser,
                            child: const Text('Create User'),
                          ),
                  ],
                ),
              ),
            ),
    );
  }
}
