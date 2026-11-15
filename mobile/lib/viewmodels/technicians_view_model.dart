import 'package:flutter/foundation.dart';

import '../models/technician.dart';
import '../services/technicians_service.dart';

class TechniciansViewModel extends ChangeNotifier {
  TechniciansViewModel(this.service);

  final TechniciansService service;
  List<Technician> technicians = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      technicians = await service.list();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> saveTechnician(
    Technician technician, {
    Technician? existing,
  }) async {
    try {
      String? temporaryPassword;
      if (existing?.id == null) {
        temporaryPassword = await service.create(technician);
      } else {
        await service.update(existing!.id!, technician);
      }
      await load();
      return temporaryPassword;
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> toggleStatus(int index) async {
    final technician = technicians[index];
    if (technician.id == null) return;
    try {
      await service.setStatus(technician.id!, !technician.active);
      await load();
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<String?> resetPassword(Technician technician) async {
    if (technician.id == null) return null;
    try {
      return await service.resetPassword(technician.id!);
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }
}
