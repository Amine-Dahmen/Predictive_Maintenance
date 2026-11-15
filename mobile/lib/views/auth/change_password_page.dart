import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../services/api_client.dart';
import '../home/role_home_page.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.role,
    required this.apiClient,
    required this.userName,
  });

  final AppRole role;
  final ApiClient apiClient;
  final String userName;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.apiClient.request(
        'POST',
        '/auth/change-password',
        body: {
          'ancienMotDePasse': _currentController.text,
          'nouveauMotDePasse': _newController.text,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RoleHomePage(
            role: widget.role,
            apiClient: widget.apiClient,
            userName: widget.userName,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de modifier le mot de passe.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFC),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Sécurisez votre compte'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: BorderSide(color: Colors.blueGrey.shade100),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const CircleAvatar(
                            radius: 34,
                            backgroundColor: Color(0xFFE5F7F5),
                            child: Icon(
                              Icons.lock_reset_rounded,
                              size: 36,
                              color: Color(0xFF087A7A),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Premier accès',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF142B45),
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Vous devez remplacer votre mot de passe provisoire avant de continuer.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.blueGrey.shade600),
                          ),
                          const SizedBox(height: 24),
                          _passwordField(
                            _currentController,
                            'Mot de passe provisoire',
                          ),
                          const SizedBox(height: 14),
                          _passwordField(
                            _newController,
                            'Nouveau mot de passe',
                            validator: (value) =>
                                value != null && value.length >= 12
                                ? null
                                : '12 caractères minimum',
                          ),
                          const SizedBox(height: 14),
                          _passwordField(
                            _confirmationController,
                            'Confirmer le nouveau mot de passe',
                            validator: (value) => value == _newController.text
                                ? null
                                : 'Les mots de passe sont différents',
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _submit,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: Text(
                                _isLoading
                                    ? 'Modification...'
                                    : 'Enregistrer et continuer',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      textInputAction: TextInputAction.next,
      validator:
          validator ??
          (value) =>
              value == null || value.isEmpty ? 'Champ obligatoire' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
      ),
    );
  }
}
