import 'package:flutter/material.dart';

import '../../config/api_config.dart';

/// Ligne « Serveur : 192.168.45.116:3000 » de l'écran de connexion, avec la modification de l'adresse.
class ServerAddressTile extends StatefulWidget {
  const ServerAddressTile({super.key});

  @override
  State<ServerAddressTile> createState() => _ServerAddressTileState();
}

class _ServerAddressTileState extends State<ServerAddressTile> {
  Future<void> _edit() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const ServerSettingsDialog(),
    );
    if (changed == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: _edit,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Serveur : ${ApiConfig.displayAddress}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const Text(
            'Modifier',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class ServerSettingsDialog extends StatefulWidget {
  const ServerSettingsDialog({super.key});

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late final _address = TextEditingController(text: ApiConfig.displayAddress);
  String? _message;
  bool _ok = false;
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  String? get _url => ApiConfig.normalize(_address.text);

  Future<void> _test() async {
    final url = _url;
    if (url == null) {
      setState(() {
        _ok = false;
        _message = 'Adresse invalide. Exemple : 192.168.45.116';
      });
      return;
    }
    setState(() => _busy = true);
    final error = await ApiConfig.check(url);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = error == null;
      _message = error ?? 'Connexion réussie à $url';
    });
  }

  Future<void> _save() async {
    final url = _url;
    if (url == null) {
      setState(() => _message = 'Adresse invalide. Exemple : 192.168.45.116');
      return;
    }
    await ApiConfig.save(url);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adresse du serveur'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adresse IP du PC qui fait tourner le backend (port 3000 par défaut). '
            'Sur le PC : « ip -4 addr » (Linux) ou « ipconfig » (Windows).',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Adresse IP ou URL',
              hintText: '192.168.45.116',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _message = null),
          ),
          if (_url != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('→ $_url', style: const TextStyle(fontSize: 12)),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _ok
                      ? Colors.green.shade700
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          await ApiConfig.reset();
          if (context.mounted) Navigator.pop(context, true);
        },
        child: const Text('Par défaut'),
      ),
      TextButton(onPressed: _busy ? null : _test, child: const Text('Tester')),
      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
    ],
  );
}
