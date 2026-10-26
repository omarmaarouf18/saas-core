import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../courier/courier_shell.dart';
import '../customer/customer_shell.dart';
import '../owner/owner_shell.dart';
import 'login_page.dart';
import 'unsupported_role_page.dart';

/// The signed-in home: the shell of the user's role (customer `user`,
/// owner, courier `employee`), [UnsupportedRolePage] for any other role,
/// and [LoginPage] when the session is gone. Refreshes the profile once
/// when it opens (role, verification and account state can change between
/// sessions), as the old HomeScreen did.
class RoleHome extends StatefulWidget {
  const RoleHome({super.key});

  @override
  State<RoleHome> createState() => _RoleHomeState();
}

class _RoleHomeState extends State<RoleHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.token != null) auth.fetchUserProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return switch (user?.role) {
      null => const LoginPage(),
      'user' => const CustomerShell(),
      'owner' => const OwnerShell(),
      'employee' => const CourierShell(),
      _ => const UnsupportedRolePage(),
    };
  }
}
