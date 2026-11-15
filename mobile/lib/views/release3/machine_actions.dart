import 'package:flutter/material.dart';

import '../../services/api_client.dart';

/// Dialogues de la fiche machine pour la Release 3.

String _error(Object e) => e is ApiException ? e.message : 'Action impossible.';

void _snack(BuildContext context, String message) => ScaffoldMessenger.maybeOf(
  context,
)?.showSnackBar(SnackBar(content: Text(message)));

/// Possède les champs de saisie d'un dialogue : ils sont libérés quand le dialogue a vraiment disparu
/// (et non dès le retour de showDialog, pendant que l'animation de fermeture les affiche encore).
class _Fields extends StatefulWidget {
  const _Fields({required this.initial, required this.builder});

  final List<String> initial;
  final Widget Function(BuildContext context, List<TextEditingController> c)
  builder;

  @override
  State<_Fields> createState() => _FieldsState();
}

class _FieldsState extends State<_Fields> {
  late final List<TextEditingController> _c = [
    for (final t in widget.initial) TextEditingController(text: t),
  ];

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _c);
}

double? parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// US-29 : déclaration manuelle d'une panne (crée une intervention curative).
/// Responsable : la réparation peut être affectée tout de suite (US-14).
/// Technicien ([selfAssign]) : il déclare la panne qu'il constate et la réparation lui est affectée.
Future<bool> showDeclareFailureDialog(
  BuildContext context,
  ApiClient api,
  int machineId, {
  bool selfAssign = false,
}) async {
  var technicians = const <Map<String, dynamic>>[];
  if (!selfAssign) {
    try {
      final r = await api.request(
        'GET',
        '/techniciens',
        query: {'statut': 'ACTIF'},
      );
      technicians = r is List
          ? r.whereType<Map<String, dynamic>>().toList()
          : const [];
    } catch (_) {
      // l'affectation pourra se faire plus tard depuis l'intervention
    }
  }
  if (!context.mounted) return false;
  int? technicianId;
  var deadlineHours = 4;
  var priorite = 'URGENTE';
  var startedAgo = 0; // minutes
  String? error;
  var saving = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _Fields(
      initial: [''],
      builder: (context, fields) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            selfAssign ? 'Prendre en charge la panne' : 'Déclarer une panne',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fields[0],
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description de la panne',
                    hintText: 'Ex. moteur bloqué, fuite d’huile…',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: startedAgo,
                  decoration: const InputDecoration(
                    labelText: 'Début de la panne',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Maintenant')),
                    DropdownMenuItem(value: 15, child: Text('Il y a 15 min')),
                    DropdownMenuItem(value: 60, child: Text('Il y a 1 h')),
                    DropdownMenuItem(value: 240, child: Text('Il y a 4 h')),
                  ],
                  onChanged: (v) => setState(() => startedAgo = v ?? 0),
                ),
                DropdownButtonFormField<String>(
                  initialValue: priorite,
                  decoration: const InputDecoration(labelText: 'Priorité'),
                  items: const [
                    DropdownMenuItem(value: 'URGENTE', child: Text('Urgente')),
                    DropdownMenuItem(value: 'HAUTE', child: Text('Haute')),
                    DropdownMenuItem(value: 'MOYENNE', child: Text('Moyenne')),
                  ],
                  onChanged: (v) => setState(() => priorite = v ?? 'URGENTE'),
                ),
                if (!selfAssign)
                  DropdownButtonFormField<int?>(
                    initialValue: technicianId,
                    decoration: const InputDecoration(
                      labelText: 'Réparation affectée à',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Plus tard'),
                      ),
                      for (final t in technicians)
                        DropdownMenuItem(
                          value: (t['id'] as num).toInt(),
                          child: Text(
                            '${t['prenom'] ?? ''} ${t['nom'] ?? ''}'.trim(),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => technicianId = v),
                  ),
                if (technicianId != null)
                  DropdownButtonFormField<int>(
                    initialValue: deadlineHours,
                    decoration: const InputDecoration(labelText: 'Échéance'),
                    items: const [
                      DropdownMenuItem(value: 4, child: Text('Dans 4 h')),
                      DropdownMenuItem(value: 24, child: Text('Dans 24 h')),
                      DropdownMenuItem(value: 72, child: Text('Dans 3 jours')),
                    ],
                    onChanged: (v) => setState(() => deadlineHours = v ?? 4),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (fields[0].text.trim().length < 3) {
                        setState(
                          () => error =
                              'Décrivez la panne (3 caractères minimum).',
                        );
                        return;
                      }
                      setState(() => saving = true);
                      try {
                        await api.request(
                          'POST',
                          '/machines/$machineId/pannes',
                          body: {
                            'description': fields[0].text.trim(),
                            'priorite': priorite,
                            'debutPanne': DateTime.now()
                                .toUtc()
                                .subtract(Duration(minutes: startedAgo))
                                .toIso8601String(),
                            if (technicianId != null)
                              'technicienId': technicianId,
                            if (technicianId != null)
                              'echeance': DateTime.now()
                                  .toUtc()
                                  .add(Duration(hours: deadlineHours))
                                  .toIso8601String(),
                          },
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        setState(() {
                          error = _error(e);
                          saving = false;
                        });
                      }
                    },
              child: const Text('Déclarer'),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok == true && context.mounted) {
    _snack(
      context,
      selfAssign
          ? 'Panne déclarée : la réparation est dans « Mes interventions ».'
          : technicianId == null
          ? 'Panne déclarée : réparation à affecter (Interventions ou fiche machine).'
          : 'Panne déclarée et réparation affectée au technicien.',
    );
  }
  return ok == true;
}

/// US-39 : calibration d'un capteur. Mise à zéro (la valeur actuelle devient la référence) ou gain / offset.
Future<bool> showCalibrationDialog(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> sensor,
) async {
  final unit = sensor['unite']?.toString() ?? '';
  var mode = 'reference';
  String? error;
  var saving = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _Fields(
      initial: [
        '0',
        '${sensor['calibrationGain'] ?? 1}',
        '${sensor['calibrationOffset'] ?? 0}',
      ],
      builder: (context, fields) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Calibrer ${sensor['identifiant'] ?? 'le capteur'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Valeur actuelle : ${sensor['derniereValeur'] ?? '—'} $unit\n'
                  'Réglage actuel : gain ${sensor['calibrationGain'] ?? 1}, '
                  'offset ${sensor['calibrationOffset'] ?? 0}',
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'reference',
                      label: Text('Valeur de référence'),
                    ),
                    ButtonSegment(
                      value: 'manuel',
                      label: Text('Gain / offset'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setState(() => mode = s.first),
                ),
                const SizedBox(height: 8),
                if (mode == 'reference') ...[
                  const Text(
                    'Mettez la machine dans un état connu (ex. moteur arrêté : 0 A) '
                    'ou mesurez avec un appareil de référence, puis saisissez la vraie valeur.',
                    style: TextStyle(fontSize: 12),
                  ),
                  TextField(
                    controller: fields[0],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Valeur réelle ($unit)',
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: fields[1],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Gain (multiplicateur)',
                    ),
                  ),
                  TextField(
                    controller: fields[2],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(labelText: 'Offset ($unit)'),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final Map<String, dynamic> body;
                      if (mode == 'reference') {
                        final r = parseNumber(fields[0].text);
                        if (r == null) {
                          return setState(
                            () => error = 'Valeur de référence invalide.',
                          );
                        }
                        body = {'valeurReference': r};
                      } else {
                        final g = parseNumber(fields[1].text);
                        final o = parseNumber(fields[2].text);
                        if (g == null || g <= 0 || o == null) {
                          return setState(
                            () => error =
                                'Gain (> 0) et offset numériques obligatoires.',
                          );
                        }
                        body = {'gain': g, 'offset': o};
                      }
                      setState(() => saving = true);
                      try {
                        await api.request(
                          'PATCH',
                          '/capteurs/${sensor['id']}/calibration',
                          body: body,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        setState(() {
                          error = _error(e);
                          saving = false;
                        });
                      }
                    },
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok == true && context.mounted) {
    _snack(
      context,
      'Calibration enregistrée : appliquée aux prochaines mesures.',
    );
  }
  return ok == true;
}

/// US-37 : remplacement d'un capteur défectueux.
Future<bool> showReplaceSensorDialog(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> sensor,
) async {
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _Fields(
      initial: [''],
      builder: (context, fields) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Remplacer ${sensor['identifiant']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'L’ancien capteur est retiré : son historique est conservé et ses alertes '
                'ouvertes sont clôturées. Les prochaines mesures iront au nouveau capteur.',
              ),
              TextField(
                controller: fields[0],
                decoration: const InputDecoration(
                  labelText: 'Identifiant du nouveau capteur (facultatif)',
                  hintText: 'généré automatiquement',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await api.request(
                    'POST',
                    '/capteurs/${sensor['id']}/remplacer',
                    body: {
                      if (fields[0].text.trim().isNotEmpty)
                        'identifiant': fields[0].text.trim(),
                    },
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  setState(() => error = _error(e));
                }
              },
              child: const Text('Remplacer'),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok == true && context.mounted) _snack(context, 'Capteur remplacé.');
  return ok == true;
}

/// US-31 : marquer une alerte comme fausse alerte.
Future<bool> showFalseAlarmDialog(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> alert,
) async {
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _Fields(
      initial: [''],
      builder: (context, fields) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Fausse alerte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'L’alerte sera clôturée et exclue des statistiques. '
                'Expliquez pourquoi elle est fausse.',
              ),
              TextField(
                controller: fields[0],
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Motif',
                  hintText: 'Ex. capteur déplacé pendant le nettoyage',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                if (fields[0].text.trim().length < 3) {
                  return setState(
                    () => error = 'Motif obligatoire (3 caractères minimum).',
                  );
                }
                try {
                  await api.request(
                    'PATCH',
                    '/alertes/${alert['id']}/fausse-alerte',
                    body: {'commentaire': fields[0].text.trim()},
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  setState(() => error = _error(e));
                }
              },
              child: const Text('Marquer'),
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

/// US-13 / US-14 : intervention prédictive planifiée depuis une alerte (responsable), affectée tout de
/// suite ou plus tard. L'alerte passe « prise en compte » ; elle est clôturée avec l'intervention.
Future<bool> showPlanFromAlertDialog(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> alert,
) async {
  var technicians = const <Map<String, dynamic>>[];
  try {
    final r = await api.request(
      'GET',
      '/techniciens',
      query: {'statut': 'ACTIF'},
    );
    technicians = r is List
        ? r.whereType<Map<String, dynamic>>().toList()
        : const [];
  } catch (_) {}
  if (!context.mounted) return false;
  var priorite = alert['niveau'] == 'CRITIQUE' ? 'URGENTE' : 'HAUTE';
  var hours = alert['niveau'] == 'CRITIQUE' ? 4 : 24;
  int? technicianId;
  String? error;
  var saving = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _Fields(
      initial: [
        'Contrôle suite à l’alerte ${alert['typeMesure'] ?? ''} '
            '(${alert['valeur'] ?? ''} ${alert['unite'] ?? ''}, seuil ${alert['seuilDepasse'] ?? ''})',
      ],
      builder: (context, fields) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Planifier une intervention · ${alert['machineCode'] ?? ''}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fields[0],
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Travail à réaliser',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: priorite,
                  decoration: const InputDecoration(labelText: 'Priorité'),
                  items: const [
                    DropdownMenuItem(value: 'URGENTE', child: Text('Urgente')),
                    DropdownMenuItem(value: 'HAUTE', child: Text('Haute')),
                    DropdownMenuItem(value: 'MOYENNE', child: Text('Moyenne')),
                    DropdownMenuItem(value: 'BASSE', child: Text('Basse')),
                  ],
                  onChanged: (v) => setState(() => priorite = v ?? priorite),
                ),
                DropdownButtonFormField<int>(
                  initialValue: hours,
                  decoration: const InputDecoration(labelText: 'Échéance'),
                  items: const [
                    DropdownMenuItem(value: 4, child: Text('Dans 4 h')),
                    DropdownMenuItem(value: 24, child: Text('Dans 24 h')),
                    DropdownMenuItem(value: 72, child: Text('Dans 3 jours')),
                  ],
                  onChanged: (v) => setState(() => hours = v ?? hours),
                ),
                DropdownButtonFormField<int?>(
                  initialValue: technicianId,
                  decoration: const InputDecoration(labelText: 'Affectée à'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Plus tard'),
                    ),
                    for (final t in technicians)
                      DropdownMenuItem(
                        value: (t['id'] as num).toInt(),
                        child: Text(
                          '${t['prenom'] ?? ''} ${t['nom'] ?? ''}'.trim(),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => technicianId = v),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (fields[0].text.trim().length < 3) {
                        return setState(
                          () => error = 'Décrivez le travail à réaliser.',
                        );
                      }
                      setState(() => saving = true);
                      final echeance = DateTime.now()
                          .toUtc()
                          .add(Duration(hours: hours))
                          .toIso8601String();
                      try {
                        final created = await api.request(
                          'POST',
                          '/interventions',
                          body: {
                            'type': 'PREDICTIVE',
                            'alerteId': alert['id'],
                            'description': fields[0].text.trim(),
                            'priorite': priorite,
                            'echeance': echeance,
                          },
                        );
                        if (technicianId != null && created is Map) {
                          await api.request(
                            'PATCH',
                            '/interventions/${created['id']}/affecter',
                            body: {
                              'technicienId': technicianId,
                              'echeance': echeance,
                              'priorite': priorite,
                            },
                          );
                        }
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        setState(() {
                          error = _error(e);
                          saving = false;
                        });
                      }
                    },
              child: const Text('Planifier'),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok == true && context.mounted) {
    _snack(
      context,
      technicianId == null
          ? 'Intervention planifiée : à affecter dans Interventions.'
          : 'Intervention planifiée et affectée au technicien.',
    );
  }
  return ok == true;
}
