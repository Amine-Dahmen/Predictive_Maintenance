import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../common.dart';

/// US-46 : mise à jour du firmware de la carte ESP32 d'une machine.
class FirmwarePage extends StatefulWidget {
  const FirmwarePage({
    super.key,
    required this.apiClient,
    required this.machine,
  });

  final ApiClient apiClient;
  final Map<String, dynamic> machine;

  @override
  State<FirmwarePage> createState() => _FirmwarePageState();
}

class _FirmwarePageState extends State<FirmwarePage> {
  List<Map<String, dynamic>> _versions = const [];
  List<Map<String, dynamic>> _history = const [];
  String? _selected;
  String? _error;
  bool _loading = true;
  bool _sending = false;

  int get _id => widget.machine['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        widget.apiClient.request('GET', '/firmware/versions'),
        widget.apiClient.request('GET', '/machines/$_id/firmware'),
      ]);
      if (!mounted) return;
      setState(() {
        _versions = (r[0] as List).whereType<Map<String, dynamic>>().toList();
        _history = (r[1] as List).whereType<Map<String, dynamic>>().toList();
        _selected ??= _versions.isEmpty
            ? null
            : _versions.first['version'] as String;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Chargement impossible.';
        _loading = false;
      });
    }
  }

  Future<void> _deploy() async {
    final version = _selected;
    if (version == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Installer la version $version ?'),
        content: const Text(
          'La carte télécharge la nouvelle version, vérifie chaque fichier puis redémarre '
          '(quelques secondes sans mesures). Elle revient seule à l’ancienne version si la '
          'nouvelle ne démarre pas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Installer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sending = true);
    try {
      await widget.apiClient.request(
        'POST',
        '/machines/$_id/firmware',
        body: {'version': version},
      );
      await _load();
    } catch (e) {
      setState(
        () => _error = e is ApiException ? e.message : 'Envoi impossible.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Tone _tone(String s) => switch (s) {
    'REUSSI' => Tone.ok,
    'ECHEC' => Tone.danger,
    _ => Tone.info,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Firmware · ${widget.machine['code']}'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Version en service : ${widget.machine['firmwareVersion'] ?? 'inconnue'}',
                    ),
                    const SizedBox(height: 12),
                    if (_versions.isEmpty)
                      const Text(
                        'Aucune version publiée. Sur le serveur : npm run firmware:publier',
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selected,
                        decoration: const InputDecoration(
                          labelText: 'Version à installer',
                        ),
                        items: [
                          for (final v in _versions)
                            DropdownMenuItem(
                              value: v['version'] as String,
                              child: Text(
                                '${v['version']} (${v['fichiers']} fichiers)',
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _selected = v),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _sending ? null : _deploy,
                        icon: const Icon(Icons.system_update_alt),
                        label: const Text('Mettre à jour la carte'),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Historique',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_history.isEmpty) const Text('Aucune mise à jour.'),
              for (final d in _history)
                ListTile(
                  title: Text('Version ${d['version']}'),
                  subtitle: Text(
                    '${d['message'] ?? ''}\n${d['updatedAt'] ?? ''}',
                  ),
                  isThreeLine: true,
                  trailing: StatusChip(
                    d['statut'].toString(),
                    _tone(d['statut'].toString()),
                  ),
                ),
            ],
          ),
  );
}
