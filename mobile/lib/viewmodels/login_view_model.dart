import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/offline_store.dart';
import '../services/auth_service.dart';

class LoginViewModel extends ChangeNotifier {
  // US-28 : cache et brouillons conservés sur le téléphone
  final apiClient = ApiClient(store: PreferencesOfflineStore());
  late final authService = AuthService(apiClient);
  bool isLoading = false;
  String? errorMessage;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  Future<AuthSession?> login() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      errorMessage = 'Veuillez saisir votre e-mail et votre mot de passe.';
      notifyListeners();
      return null;
    }
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await authService.login(
        emailController.text.trim(),
        passwordController.text,
      );
    } catch (error) {
      errorMessage = error is ApiException
          ? error.message
          : 'La connexion a échoué : $error';
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
