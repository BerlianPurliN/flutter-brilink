import 'package:brilink/pages/laporan_page.dart';
import 'package:brilink/pages/payment_method_crud.dart';
import 'package:flutter/material.dart';
import 'package:brilink/pages/login_page.dart';
import 'package:brilink/pages/home_page.dart';

class AppRoutes {
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String laporan = '/laporan';
  static const String payment = '/payment-method';

  static Map<String, WidgetBuilder> get routes => {
    login: (context) => const LoginPage(),
    home: (context) => const HomePage(),
    laporan: (context) => const LaporanPage(),
    payment: (context) => const PaymentMethodCrudPage(),
  };
}
