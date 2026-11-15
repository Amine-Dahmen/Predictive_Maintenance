import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../common.dart';

class ResponsablesPage extends StatefulWidget {
  const ResponsablesPage({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<ResponsablesPage> createState() => _ResponsablesPageState();
}

class _ResponsablesPageState extends State<ResponsablesPage> {
  List<Map<String, dynamic>> _responsables = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _status;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.apiClient.request(
        'GET',
        '/responsables',
        query: {
          'statut': ?_status,
          'recherche': ?(_search.trim().isEmpty ? null : _search.trim()),
        },
      );
      if (!mounted) return;
      setState(() {
        _responsables = result is List
            ? result.whereType<Map<String, dynamic>>().toList()
            : const [];
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de charger les comptes responsables.';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered => _responsables.where((user) {
    if (_status != null && user['statut'] != _status) return false;
    final search = _search.trim().toLowerCase();
    if (search.isEmpty) return true;
    final name = '${user['prenom'] ?? ''} ${user['nom'] ?? ''}'.toLowerCase();
    return name.contains(search) ||
        user['email']?.toString().toLowerCase().contains(search) == true;
  }).toList();

  Future<void> _createOrEdit([Map<String, dynamic>? existing]) async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ResponsableFormDialog(responsable: existing),
    );
    if (values == null || !mounted) return;
    try {
      final result = existing == null
          ? await widget.apiClient.request(
              'POST',
              '/responsables',
              body: values,
            )
          : await widget.apiClient.request(
              'PATCH',
              '/responsables/${existing['id']}',
              body: values,
            );
      await _load();
      if (existing == null && result is Map) {
        final temporaryPassword = result['motDePasseProvisoire']?.toString();
        if (temporaryPassword != null && mounted) {
          await _showTemporaryPassword(temporaryPassword);
        }
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> user) async {
    final active = user['statut'] == 'ACTIF';
    final action = active ? 'désactiver' : 'activer';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmer : $action le compte ?'),
        content: Text(
          active
              ? 'Le responsable sera immédiatement déconnecté.'
              : 'Le responsable pourra se reconnecter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(active ? 'Désactiver' : 'Activer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.apiClient.request(
        'PATCH',
        '/responsables/${user['id']}/statut',
        body: {'statut': active ? 'DESACTIVE' : 'ACTIF'},
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showTemporaryPassword(String password) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Compte créé'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Communiquez ce mot de passe provisoire au responsable. '
            'Il ne sera plus affiché.',
          ),
          const SizedBox(height: 12),
          SelectableText(
            password,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Terminé'),
        ),
      ],
    ),
  );

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is ApiException
        ? error.message
        : 'La modification du compte a échoué.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final users = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comptes responsables'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOrEdit(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Créer un compte'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Rechercher',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Statut du compte',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Tous les comptes'),
                    ),
                    DropdownMenuItem(value: 'ACTIF', child: Text('Actifs')),
                    DropdownMenuItem(
                      value: 'DESACTIVE',
                      child: Text('Désactivés'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _status = value);
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                children: [
                  if (!_isLoading && _errorMessage == null && users.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 28),
                      child: Center(child: Text('Aucun compte responsable.')),
                    ),
                  ...users.map(_responsableCard),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _responsableCard(Map<String, dynamic> user) {
    final active = user['statut'] == 'ACTIF';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            child: Icon(active ? Icons.admin_panel_settings : Icons.person_off),
          ),
          title: Text('${user['prenom'] ?? ''} ${user['nom'] ?? ''}'.trim()),
          subtitle: Text(
            '${user['email'] ?? ''}\n'
            '${user['telephone'] ?? 'Téléphone non renseigné'} · '
            '${active ? 'Actif' : 'Désactivé'} · Rôle : Responsable',
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'edit') _createOrEdit(user);
              if (action == 'status') _toggleStatus(user);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Modifier')),
              PopupMenuItem(
                value: 'status',
                child: Text(active ? 'Désactiver' : 'Activer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsableFormDialog extends StatefulWidget {
  const _ResponsableFormDialog({this.responsable});

  final Map<String, dynamic>? responsable;

  @override
  State<_ResponsableFormDialog> createState() => _ResponsableFormDialogState();
}

class _ResponsableFormDialogState extends State<_ResponsableFormDialog> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  String? _error;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController(
      text: widget.responsable?['prenom']?.toString() ?? '',
    );
    _lastName = TextEditingController(
      text: widget.responsable?['nom']?.toString() ?? '',
    );
    _email = TextEditingController(
      text: widget.responsable?['email']?.toString() ?? '',
    );
    _phone = TextEditingController(
      text: widget.responsable?['telephone']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final email = _email.text.trim();
    if (firstName.isEmpty || lastName.isEmpty || !_validEmail(email)) {
      setState(
        () => _error = 'Renseignez le prénom, le nom et un e-mail valide.',
      );
      return;
    }
    Navigator.pop(context, {
      'prenom': firstName,
      'nom': lastName,
      'email': email,
      if (_phone.text.trim().isNotEmpty) 'telephone': _phone.text.trim(),
    });
  }

  bool _validEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.responsable == null
          ? 'Créer un responsable'
          : 'Modifier le responsable',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _firstName,
            decoration: const InputDecoration(labelText: 'Prénom'),
          ),
          TextField(
            controller: _lastName,
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail'),
          ),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Téléphone (facultatif)',
            ),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Rôle attribué : Responsable'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
    ],
  );
}
