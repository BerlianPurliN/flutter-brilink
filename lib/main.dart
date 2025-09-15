import 'package:flutter/material.dart';
import 'package:brilink/app_routes.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:brilink/widgets/auth_wrapper.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('id_ID', null);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthWrapper(),
      routes: AppRoutes.routes,
      debugShowCheckedModeBanner: false, //INI BUAT WATERMARK
    );
  }
}
