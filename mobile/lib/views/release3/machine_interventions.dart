import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../common.dart';
import '../operations/interventions_page.dart';
import 'machine_actions.dart';

/// Interventions ouvertes d'une machine, sur sa fiche. Une machine « en panne » le reste jusqu'à la
/// clôture de sa réparation par le technicien (« machine remise en service ») : cette carte montre
/// où en est cette réparation et qui doit agir.
///  - responsable : affecter / réaffecter (US-14), ouvrir le détail
///  - technicien : ses interventions sur la machine, démarrer / compte rendu / clôturer (US-06, US-07)
class MachineInterventionsCard extends StatefulWidget {
  const MachineInterventionsCard({
    super.key,
    required this.apiClient,
    required this.machineId,
    required this.machineState,
    required this.isTechnician,
    required this.canManage,
    this.onChanged,
  });

  final ApiClient apiClient;
  final int machineId;
  final String machineState;
  final bool isTechnician;
  final bool canManage;
  final VoidCallback? onChanged;

  @override
  State<MachineInterventionsCard> createState() =>
      _MachineInterventionsCardState();
}

class _MachineInterventionsCardState extends State<MachineInterventionsCard> {
  static const _open = {'A_AFFECTER', 'AFFECTEE', 'EN_COURS'};
  List<Map<String, dynamic>> _items = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final query = {'machineId': '${widget.machineId}'};
      final results = await Future.wait([
        widget.apiClient.request('GET', '/interventions', query: query),
        // technicien : aussi celles de la machine que personne n'a prises
        if (widget.isTechnician)
          widget.apiClient.request(
            'GET',
            '/interventions',
            query: {...query, 'aPrendre': 'true'},
          ),
      ]);
      if (!mounted) return;
      final seen = <dynamic>{};
      setState(() {
        _items = [
          for (final r in results)
            if (r is List)
              for (final i in r.whereType<Map<String, dynamic>>())
                if (_open.contains(i['statut']) && seen.add(i['id'])) i,
        ];
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _changed() async {
    await _load();
    widget.onChanged?.call();
  }

  String? get _hint {
    final panne = widget.machineState == 'PANNE';
    if (_items.isEmpty) {
      if (!panne) return null;
      return widget.canManage
          ? 'Machine en panne sans réparation planifiée : déclarez la panne (bouton ⚠ en haut) ou '
                'planifiez une intervention depuis l’alerte critique, puis affectez-la à un technicien.'
          : widget.isTechnician
          ? 'Machine en panne et personne n’est sur la réparation : prenez la panne en charge.'
          : 'Machine en panne : réparation pas encore planifiée.';
    }
    if (panne) {
      return 'La machine redevient disponible quand le technicien clôture la réparation avec '
          '« Machine remise en service ».';
    }
    return null;
  }

  String _label(String s) => switch (s) {
    'A_AFFECTER' => 'À affecter',
    'AFFECTEE' => 'Affectée',
    'EN_COURS' => 'En cours',
    _ => s,
  };

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final hint = _hint;
    if (_items.isEmpty && hint == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isTechnician
                  ? 'Mes interventions sur cette machine'
                  : 'Interventions en cours',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(hint, style: const TextStyle(fontSize: 12)),
              ),
            if (widget.isTechnician &&
                _items.isEmpty &&
                widget.machineState == 'PANNE')
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () async {
                    if (await showDeclareFailureDialog(
                      context,
                      widget.apiClient,
                      widget.machineId,
                      selfAssign: true,
                    )) {
                      _changed();
                    }
                  },
                  icon: const Icon(Icons.pan_tool_alt_outlined),
                  label: const Text('Prendre en charge la panne'),
                ),
              ),
            for (final i in _items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '${i['type']} · ${i['description'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  i['technicienNom'] == null
                      ? 'Non affectée'
                      : 'Technicien : ${i['technicienPrenom'] ?? ''} ${i['technicienNom']}',
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    StatusChip(
                      _label('${i['statut']}'),
                      i['statut'] == 'A_AFFECTER' ? Tone.warn : Tone.info,
                    ),
                    if (widget.isTechnician &&
                        i['statut'] == 'A_AFFECTER' &&
                        i['technicienId'] == null)
                      IconButton(
                        tooltip: 'Prendre en charge',
                        icon: const Icon(Icons.pan_tool_alt_outlined),
                        onPressed: () async {
                          if (await takeIntervention(
                            context,
                            widget.apiClient,
                            i,
                          ))
                            _changed();
                        },
                      ),
                    if (widget.canManage &&
                        (i['statut'] == 'A_AFFECTER' ||
                            i['statut'] == 'AFFECTEE'))
                      IconButton(
                        tooltip: i['statut'] == 'A_AFFECTER'
                            ? 'Affecter'
                            : 'Réaffecter',
                        icon: const Icon(Icons.person_add_alt),
                        onPressed: () async {
                          if (await assignIntervention(
                            context,
                            widget.apiClient,
                            i,
                          ))
                            _changed();
                        },
                      ),
                  ],
                ),
                onTap: () async {
                  final changed = await openInterventionDetail(
                    context,
                    apiClient: widget.apiClient,
                    intervention: i,
                    isTechnician: widget.isTechnician,
                    canManage: widget.canManage,
                  );
                  if (changed) _changed();
                },
              ),
          ],
        ),
      ),
    );
  }
}
