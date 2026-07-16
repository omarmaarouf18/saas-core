import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/owner_provider.dart';
import 'providers/employee_jobs_provider.dart';
import 'providers/marketplace_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = bypassBadCertificate;
  }
}

void main() {
  // Wire HTTP certificate overrides in debug mode for self-signed certificates.
  if (kDebugMode) {
    HttpOverrides.global = DevHttpOverrides();
  }
  
  final apiClient = ApiClient();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => OwnerProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => EmployeeJobsProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => MarketplaceProvider(apiClient)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    
    return MaterialApp(
      title: 'Quick Delivery',
      theme: quickDeliveryTheme,
      debugShowCheckedModeBanner: false,
      home: auth.isAuthenticated ? const HomeScreen() : const LoginScreen(),
    );
  }
}
