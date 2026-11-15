import 'package:flutter/foundation.dart';

import '../services/dashboard_service.dart';

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel(this.service, {required this.isChef});

  final DashboardService service;
  final bool isChef;
  DashboardSnapshot? snapshot;
  bool isLoading = true;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      snapshot = isChef
          ? await service.loadChefDashboard()
          : await service.loadTechnicianDashboard();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
