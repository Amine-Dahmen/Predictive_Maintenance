import 'package:flutter/material.dart';

import 'app.dart';
import 'config/api_config.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.load(); // adresse du serveur enregistrée sur le téléphone
  runApp(const MaintenancePredictiveApp());
}
