import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../auth/login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.role, required this.apiClient});

  final AppRole role;
  final ApiClient apiClient;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  bool _isLoggingOut = false;
  String? _errorMessage;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await widget.apiClient.request('GET', '/auth/me');
      if (!mounted) return;
      setState(() {
        _profile = data as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de charger le profil.';
        _isLoading = false;
      });
    }
  }

  Future<void> _changePassword() async {
    final values = await showDialog<_PasswordValues>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (!mounted || values == null) return;

    try {
      await widget.apiClient.request(
        'POST',
        '/auth/change-password',
        body: {
          'ancienMotDePasse': values.current,
          'nouveauMotDePasse': values.next,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe modifié avec succès.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(
        error is ApiException ? error.message : 'Modification impossible.',
      );
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      final refreshToken = widget.apiClient.refreshToken;
      if (refreshToken != null) {
        await widget.apiClient.request(
          'POST',
          '/auth/logout',
          body: {'refreshToken': refreshToken},
        );
      }
    } catch (error) {
      if (mounted) {
        _showError(
          error is ApiException ? error.message : 'Déconnexion impossible.',
        );
      }
    }
    widget.apiClient.accessToken = null;
    widget.apiClient.refreshToken = null;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _profile;
    final name = user == null
        ? widget.role.label
        : '${user['prenom'] ?? ''} ${user['nom'] ?? ''}'.trim();
    final email = user?['email']?.toString() ?? 'Compte connecté';
    final initials = name.isEmpty
        ? 'U'
        : name
              .split(' ')
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part[0].toUpperCase())
              .join();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: AppColors.steel,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                tooltip: 'Retour',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F7F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Color(0xFF087A7A),
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Mon profil',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF142B45),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Vos informations et la sécurité de votre compte',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.blueGrey.shade600,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0B3554), Color(0xFF087A7A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0B3554).withAlpha(45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white.withAlpha(35),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(color: Colors.white.withAlpha(205)),
                        ),
                        const SizedBox(height: 10),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF12C7BB).withAlpha(45),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            child: Text(
                              widget.role.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB8FFF8),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: Colors.blueGrey.shade100),
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE5F7F5),
                      child: Icon(Icons.lock_outline, color: Color(0xFF087A7A)),
                    ),
                    title: const Text(
                      'Sécurité du compte',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Modifier votre mot de passe'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _changePassword,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
                    leading: CircleAvatar(
                      backgroundColor: Colors.red.shade50,
                      child: Icon(Icons.logout, color: Colors.red.shade700),
                    ),
                    title: Text(
                      _isLoggingOut ? 'Déconnexion...' : 'Se déconnecter',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text('Fermer la session actuelle'),
                    trailing: _isLoggingOut
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _isLoggingOut ? null : _logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordValues {
  const _PasswordValues(this.current, this.next);

  final String current;
  final String next;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Changer le mot de passe'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_current, 'Mot de passe actuel'),
              _field(
                _next,
                'Nouveau mot de passe',
                validator: (value) => value != null && value.length >= 12
                    ? null
                    : '12 caractères minimum',
              ),
              _field(
                _confirmation,
                'Confirmer le mot de passe',
                validator: (value) => value == _next.text
                    ? null
                    : 'Les mots de passe sont différents',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                _PasswordValues(_current.text, _next.text),
              );
            }
          },
          child: const Text('Modifier'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: true,
        validator:
            validator ??
            (value) =>
                value == null || value.isEmpty ? 'Champ obligatoire' : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
