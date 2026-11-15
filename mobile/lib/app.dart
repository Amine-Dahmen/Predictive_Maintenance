import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'views/auth/login_page.dart';

class MaintenancePredictiveApp extends StatelessWidget {
  const MaintenancePredictiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maintenance prédictive',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const LoginPage(),
    );
  }
}
