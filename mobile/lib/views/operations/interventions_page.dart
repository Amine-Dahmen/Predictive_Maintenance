import 'dart:async';
import '../shared/live_reload.dart';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../release3/intervention_photos.dart';
import '../common.dart';

class InterventionsPage extends StatefulWidget {
  const InterventionsPage({
    super.key,
    required this.apiClient,
    required this.isTechnician,
    required this.canManage,
  });

  final ApiClient apiClient;
  final bool isTechnician;
  final bool canManage;

  @override
  State<InterventionsPage> createState() => _InterventionsPageState();
}

class _InterventionsPageState extends State<InterventionsPage>
    with LiveReload<InterventionsPage> {
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _machines = const [];
  List<Map<String, dynamic>> _technicians = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _status;
  Timer? _refreshTimer;
  // Technicien : « Mes interventions » ou « À prendre » (non affectées, extension de US-26)
  bool _toTake = false;

  @override
  void initState() {
    super.initState();
    liveReload(widget.apiClient, _load);
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isLoading) _load();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final requests = <Future<dynamic>>[
        widget.apiClient.request(
          'GET',
          '/interventions',
          query: widget.isTechnician && _toTake
              ? {'aPrendre': 'true'}
              : {'statut': ?_status},
        ),
      ];
      if (widget.canManage) {
        requests
          ..add(widget.apiClient.request('GET', '/machines'))
          ..add(widget.apiClient.request('GET', '/techniciens'));
      }
      final results = await Future.wait<dynamic>(requests);
      if (!mounted) return;
      setState(() {
        _items = _asList(results[0]);
        if (widget.canManage) {
          _machines = _asList(results[1]);
          _technicians = _asList(results[2]);
        }
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de charger les interventions.';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _asList(dynamic data) =>
      data is List ? data.whereType<Map<String, dynamic>>().toList() : const [];

  Future<void> _create() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CreateInterventionDialog(machines: _machines),
    );
    if (payload == null || !mounted) return;
    try {
      await widget.apiClient.request('POST', '/interventions', body: payload);
      await _load();
      if (mounted) _showMessage('Intervention planifiée.');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _assign(Map<String, dynamic> item) async {
    if (await assignIntervention(
      context,
      widget.apiClient,
      item,
      technicians: _technicians,
    )) {
      await _load();
    }
  }

  Future<void> _cancel(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler l’intervention ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler l’intervention'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.apiClient.request(
        'PATCH',
        '/interventions/${item['id']}/annuler',
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _take(Map<String, dynamic> item) async {
    if (await takeIntervention(context, widget.apiClient, item)) {
      setState(() => _toTake = false);
      await _load();
    }
  }

  Future<void> _start(Map<String, dynamic> item) async {
    try {
      await widget.apiClient.request(
        'PATCH',
        '/interventions/${item['id']}/demarrer',
      );
      await _load();
      if (mounted) _showMessage('Intervention démarrée.');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openDetails(Map<String, dynamic> item) async {
    final changed = await openInterventionDetail(
      context,
      apiClient: widget.apiClient,
      intervention: item,
      isTechnician: widget.isTechnician,
      canManage: widget.canManage,
    );
    if (changed) _load();
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is ApiException
        ? error.message
        : 'L’opération n’a pas pu être effectuée.';
    _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: !widget.canManage
        ? null
        : FloatingActionButton.extended(
            onPressed: _machines.isEmpty ? null : _create,
            icon: const Icon(Icons.add),
            label: const Text('Planifier'),
          ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Filtres des interventions',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualiser les interventions',
                      onPressed: _isLoading ? null : _load,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (widget.isTechnician)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Mes interventions'),
                        ),
                        ButtonSegment(value: true, label: Text('À prendre')),
                      ],
                      selected: {_toTake},
                      onSelectionChanged: (v) {
                        setState(() => _toTake = v.first);
                        _load();
                      },
                    ),
                  ),
                if (!(widget.isTechnician && _toTake))
                  DropdownButtonFormField<String?>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Statut',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('Tous les statuts'),
                      ),
                      DropdownMenuItem(
                        value: 'A_AFFECTER',
                        child: Text('À affecter'),
                      ),
                      DropdownMenuItem(
                        value: 'AFFECTEE',
                        child: Text('Affectée'),
                      ),
                      DropdownMenuItem(
                        value: 'EN_COURS',
                        child: Text('En cours'),
                      ),
                      DropdownMenuItem(
                        value: 'CLOTUREE',
                        child: Text('Clôturée'),
                      ),
                      DropdownMenuItem(
                        value: 'ANNULEE',
                        child: Text('Annulée'),
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
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              children: [
                if (_isLoading) const LinearProgressIndicator(),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Column(
                      children: [
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                if (!_isLoading && _errorMessage == null && _items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Center(
                      child: Text(
                        widget.isTechnician && _toTake
                            ? 'Aucune intervention à prendre.'
                            : 'Aucune intervention trouvée.',
                      ),
                    ),
                  ),
                ..._items.map(_interventionCard),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _interventionCard(Map<String, dynamic> item) {
    final status = item['statut']?.toString() ?? 'INCONNU';
    final canManage =
        widget.canManage && (status == 'A_AFFECTER' || status == 'AFFECTEE');
    final canStart = widget.isTechnician && status == 'AFFECTEE';
    final canTake =
        widget.isTechnician &&
        status == 'A_AFFECTER' &&
        item['technicienId'] == null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        onTap: () => _openDetails(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    widget.isTechnician
                        ? Icons.build_outlined
                        : Icons.assignment_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${item['type'] ?? 'Intervention'} · '
                    '${item['machineCode'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (item['enRetard'] == true)
                  const StatusChip('En retard', Tone.danger),
              ],
            ),
            const SizedBox(height: 8),
            Text(item['description']?.toString() ?? 'Sans description'),
            Text(
              '${item['machineNom'] ?? ''} · Priorité ${item['priorite'] ?? '—'}',
            ),
            Text(
              '${item['technicienPrenom'] ?? ''} ${item['technicienNom'] ?? ''}'
                      .trim()
                      .isEmpty
                  ? 'Non affectée'
                  : 'Technicien : ${item['technicienPrenom'] ?? ''} '
                        '${item['technicienNom'] ?? ''}',
            ),
            Text(
              'Échéance : ${_formatDate(item['echeance'] ?? item['datePrevue'])}',
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip(_statusLabel(status), _statusTone(status)),
                TextButton(
                  onPressed: () => _openDetails(item),
                  child: const Text('Détail / compte rendu'),
                ),
                if (canManage)
                  OutlinedButton(
                    onPressed: () => _assign(item),
                    child: Text(
                      status == 'AFFECTEE' ? 'Réaffecter' : 'Affecter',
                    ),
                  ),
                if (canManage)
                  TextButton(
                    onPressed: () => _cancel(item),
                    child: const Text('Annuler'),
                  ),
                if (canTake)
                  FilledButton.icon(
                    onPressed: () => _take(item),
                    icon: const Icon(Icons.pan_tool_alt_outlined),
                    label: const Text('Prendre en charge'),
                  ),
                if (canStart)
                  FilledButton(
                    onPressed: () => _start(item),
                    child: const Text('Démarrer'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Non définie';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} à $hour:$minute';
  }
}

class _CreateInterventionDialog extends StatefulWidget {
  const _CreateInterventionDialog({required this.machines});

  final List<Map<String, dynamic>> machines;

  @override
  State<_CreateInterventionDialog> createState() =>
      _CreateInterventionDialogState();
}

class _CreateInterventionDialogState extends State<_CreateInterventionDialog> {
  final _description = TextEditingController();
  String _type = 'PREVENTIVE';
  String? _machineId;
  DateTime? _plannedDate;
  String _priority = 'MOYENNE';
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selectedDate == null || !mounted) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (selectedTime == null) return;
    setState(() {
      _plannedDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  void _submit() {
    final description = _description.text.trim();
    if (description.length < 3) {
      setState(
        () => _error = 'La description doit contenir au moins 3 caractères.',
      );
      return;
    }
    final machineId = int.tryParse(_machineId ?? '');
    if (machineId == null) {
      setState(() => _error = 'Sélectionnez une machine.');
      return;
    }
    if (_type == 'PREVENTIVE' &&
        (_plannedDate == null || !_plannedDate!.isAfter(DateTime.now()))) {
      setState(() => _error = 'Choisissez une date future pour la prévention.');
      return;
    }
    Navigator.pop(context, {
      'type': _type,
      'machineId': machineId,
      'description': description,
      'priorite': _priority,
      if (_type == 'PREVENTIVE')
        'datePrevue': _plannedDate!.toUtc().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Planifier une intervention'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'PREVENTIVE', child: Text('Préventive')),
              DropdownMenuItem(value: 'CURATIVE', child: Text('Curative')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _type = value;
                  _priority = value == 'CURATIVE' ? 'URGENTE' : 'MOYENNE';
                });
              }
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: _machineId,
            decoration: const InputDecoration(labelText: 'Machine'),
            items: widget.machines
                .map(
                  (machine) => DropdownMenuItem(
                    value: machine['id']?.toString(),
                    child: Text(
                      '${machine['code'] ?? ''} · ${machine['nom'] ?? ''}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _machineId = value),
          ),
          if (_type == 'PREVENTIVE')
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _plannedDate == null
                    ? 'Date prévue'
                    : '${_plannedDate!.day}/${_plannedDate!.month}/${_plannedDate!.year} '
                          'à ${_plannedDate!.hour.toString().padLeft(2, '0')}:'
                          '${_plannedDate!.minute.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_month),
              onTap: _selectDate,
            ),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description',
              alignLabelWithHint: true,
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priorité'),
            items: const [
              DropdownMenuItem(value: 'BASSE', child: Text('Basse')),
              DropdownMenuItem(value: 'MOYENNE', child: Text('Moyenne')),
              DropdownMenuItem(value: 'HAUTE', child: Text('Haute')),
              DropdownMenuItem(value: 'URGENTE', child: Text('Urgente')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _priority = value);
            },
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
        child: const Text('Fermer'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Créer')),
    ],
  );
}

class _AssignInterventionDialog extends StatefulWidget {
  const _AssignInterventionDialog({
    required this.technicians,
    required this.initialPriority,
  });

  final List<Map<String, dynamic>> technicians;
  final String initialPriority;

  @override
  State<_AssignInterventionDialog> createState() =>
      _AssignInterventionDialogState();
}

class _AssignInterventionDialogState extends State<_AssignInterventionDialog> {
  String? _technicianId;
  DateTime? _deadline;
  String _priority = 'MOYENNE';
  String? _error;

  @override
  void initState() {
    super.initState();
    _priority = widget.initialPriority;
  }

  Future<void> _selectDeadline() async {
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selectedDate == null || !mounted) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (selectedTime == null) return;
    setState(() {
      _deadline = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  void _submit() {
    final technicianId = int.tryParse(_technicianId ?? '');
    if (technicianId == null || _deadline == null) {
      setState(() => _error = 'Sélectionnez un technicien et une échéance.');
      return;
    }
    if (!_deadline!.isAfter(DateTime.now())) {
      setState(() => _error = 'L’échéance doit être dans le futur.');
      return;
    }
    Navigator.pop(context, {
      'technicienId': technicianId,
      'echeance': _deadline!.toUtc().toIso8601String(),
      'priorite': _priority,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Affecter à un technicien'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _technicianId,
            decoration: const InputDecoration(labelText: 'Technicien'),
            items: widget.technicians
                .map(
                  (technician) => DropdownMenuItem(
                    value: technician['id']?.toString(),
                    child: Text(
                      '${technician['prenom'] ?? ''} ${technician['nom'] ?? ''}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _technicianId = value),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _deadline == null
                  ? 'Échéance'
                  : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year} '
                        'à ${_deadline!.hour.toString().padLeft(2, '0')}:'
                        '${_deadline!.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.calendar_month),
            onTap: _selectDeadline,
          ),
          DropdownButtonFormField<String>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priorité'),
            items: const [
              DropdownMenuItem(value: 'BASSE', child: Text('Basse')),
              DropdownMenuItem(value: 'MOYENNE', child: Text('Moyenne')),
              DropdownMenuItem(value: 'HAUTE', child: Text('Haute')),
              DropdownMenuItem(value: 'URGENTE', child: Text('Urgente')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _priority = value);
            },
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
      FilledButton(onPressed: _submit, child: const Text('Affecter')),
    ],
  );
}

class _InterventionDetailSheet extends StatefulWidget {
  const _InterventionDetailSheet({
    required this.apiClient,
    required this.intervention,
    required this.isTechnician,
    this.canAddPhotos = false,
    this.onChanged,
  });

  final ApiClient apiClient;
  final Map<String, dynamic> intervention;
  final bool isTechnician;
  final bool canAddPhotos;
  // Appelé quand l'intervention change (démarrage) même si la feuille est fermée d'un glissement
  final VoidCallback? onChanged;

  @override
  State<_InterventionDetailSheet> createState() =>
      _InterventionDetailSheetState();
}

class _InterventionDetailSheetState extends State<_InterventionDetailSheet> {
  final _diagnostic = TextEditingController();
  final _actions = TextEditingController();
  final _parts = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  // Version à jour renvoyée par l'API (la carte de la liste peut être périmée)
  late Map<String, dynamic> _current = widget.intervention;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _diagnostic.dispose();
    _actions.dispose();
    _parts.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final result = await widget.apiClient.request(
        'GET',
        '/interventions/${_current['id']}',
      );
      if (!mounted) return;
      if (result is Map<String, dynamic>) {
        _current = result;
        final report = result['compteRendu'];
        if (report is Map<String, dynamic>) {
          _diagnostic.text = report['diagnostic']?.toString() ?? '';
          _actions.text = report['actions']?.toString() ?? '';
          _parts.text = report['piecesUtilisees']?.toString() ?? '';
        }
      }
      setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de charger le détail.';
        _isLoading = false;
      });
    }
  }

  Future<bool> _saveReport() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final saved = await widget.apiClient.request(
        'PUT',
        '/interventions/${_current['id']}/compte-rendu',
        body: {
          'diagnostic': _diagnostic.text.trim(),
          'actions': _actions.text.trim(),
          'piecesUtilisees': _parts.text.trim(),
        },
      );
      if (mounted) {
        setState(() => _isSaving = false);
        // US-28 : sans réseau, le brouillon est gardé sur le téléphone et envoyé plus tard
        if (saved is Map && saved['horsLigne'] == true) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Hors ligne : brouillon enregistré sur le téléphone, envoi automatique au retour du réseau.',
              ),
            ),
          );
          return false; // la clôture, elle, exige le serveur
        }
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is ApiException
              ? error.message
              : 'Impossible d’enregistrer le compte rendu.';
          _isSaving = false;
        });
      }
      return false;
    }
  }

  Future<void> _closeIntervention() async {
    if (_diagnostic.text.trim().isEmpty || _actions.text.trim().isEmpty) {
      setState(
        () => _errorMessage =
            'Le diagnostic et les actions sont obligatoires pour clôturer.',
      );
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Résultat de l’intervention'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'REMISE_EN_SERVICE'),
            child: const Text('Machine remise en service'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'NON_RESOLU'),
            child: const Text('Problème non résolu'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    if (!await _saveReport() || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await widget.apiClient.request(
        'PATCH',
        '/interventions/${_current['id']}/cloturer',
        body: {'resultat': result},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de clôturer l’intervention.';
        _isSaving = false;
      });
    }
  }

  // US-06 / US-07 : le technicien démarre l'intervention depuis le détail, puis rédige le compte rendu
  Future<void> _start() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.apiClient.request(
        'PATCH',
        '/interventions/${_current['id']}/demarrer',
      );
      widget.onChanged?.call();
      await _loadDetail();
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = error is ApiException
              ? error.message
              : 'Impossible de démarrer l’intervention.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? get _guidance {
    final status = _current['statut'];
    if (widget.isTechnician) {
      return switch (status) {
        'A_AFFECTER' =>
          'Personne ne s’en occupe encore : prenez-la en charge pour la réaliser.',
        'AFFECTEE' =>
          'Démarrez l’intervention sur place pour rédiger le compte rendu.',
        'EN_COURS' =>
          'Renseignez le diagnostic et les actions, puis clôturez. '
              '« Machine remise en service » clôture aussi les alertes et la panne de la machine.',
        _ => null,
      };
    }
    return switch (status) {
      'A_AFFECTER' =>
        'À affecter à un technicien : c’est lui qui réalise et clôture l’intervention.',
      'AFFECTEE' => 'En attente du démarrage par le technicien.',
      'EN_COURS' =>
        'Le technicien réalise l’intervention ; il la clôture avec son compte rendu.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final intervention = _current;
    final isInProgress = intervention['statut'] == 'EN_COURS';
    final canEditReport = widget.isTechnician && isInProgress;
    final canStart =
        widget.isTechnician && intervention['statut'] == 'AFFECTEE';
    final canTake =
        widget.isTechnician &&
        intervention['statut'] == 'A_AFFECTER' &&
        intervention['technicienId'] == null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: _isLoading
          ? const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Intervention · ${intervention['machineCode'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(intervention['description']?.toString() ?? ''),
                  Text('Type : ${intervention['type'] ?? '—'}'),
                  Text('Priorité : ${intervention['priorite'] ?? '—'}'),
                  Text(
                    'Statut : ${_statusLabel(intervention['statut']?.toString() ?? '—')}',
                  ),
                  Text(
                    'Technicien : ${intervention['technicienPrenom'] ?? ''} '
                    '${intervention['technicienNom'] ?? ''}',
                  ),
                  if (_guidance != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _guidance!,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  if (canTake)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: FilledButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () async {
                                if (await takeIntervention(
                                  context,
                                  widget.apiClient,
                                  _current,
                                )) {
                                  widget.onChanged?.call();
                                  await _loadDetail();
                                }
                              },
                        icon: const Icon(Icons.pan_tool_alt_outlined),
                        label: const Text('Prendre en charge'),
                      ),
                    ),
                  if (canStart)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Démarrer l’intervention'),
                      ),
                    ),
                  const Divider(height: 24),
                  Text(
                    'Compte rendu',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextField(
                    controller: _diagnostic,
                    enabled: canEditReport,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Diagnostic',
                      alignLabelWithHint: true,
                    ),
                  ),
                  TextField(
                    controller: _actions,
                    enabled: canEditReport,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Actions réalisées',
                      alignLabelWithHint: true,
                    ),
                  ),
                  TextField(
                    controller: _parts,
                    enabled: canEditReport,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Pièces utilisées (facultatif)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const Divider(height: 24),
                  // US-25 : photos (ajout par le technicien affecté pendant ou après l'intervention, ou le responsable)
                  InterventionPhotos(
                    apiClient: widget.apiClient,
                    interventionId: (intervention['id'] as num).toInt(),
                    canAdd: widget.isTechnician
                        ? (isInProgress || intervention['statut'] == 'CLOTUREE')
                        : widget.canAddPhotos,
                  ),
                  if (canEditReport) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _saveReport,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Enregistrer le brouillon'),
                    ),
                    FilledButton(
                      onPressed: _isSaving ? null : _closeIntervention,
                      child: const Text('Clôturer l’intervention'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'A_AFFECTER' => 'À affecter',
  'AFFECTEE' => 'Affectée',
  'EN_COURS' => 'En cours',
  'CLOTUREE' => 'Clôturée',
  'ANNULEE' => 'Annulée',
  _ => status,
};

Tone _statusTone(String status) => switch (status) {
  'A_AFFECTER' => Tone.warn,
  'AFFECTEE' => Tone.info,
  'EN_COURS' => Tone.info,
  'CLOTUREE' => Tone.ok,
  'ANNULEE' => Tone.neutral,
  _ => Tone.neutral,
};

/// Ouvre le détail d'une intervention (liste des interventions, fiche machine).
/// Renvoie true si l'intervention a changé (démarrée, clôturée…).
Future<bool> openInterventionDetail(
  BuildContext context, {
  required ApiClient apiClient,
  required Map<String, dynamic> intervention,
  required bool isTechnician,
  bool canManage = false,
}) async {
  var started = false;
  final closed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _InterventionDetailSheet(
      apiClient: apiClient,
      intervention: intervention,
      isTechnician: isTechnician,
      canAddPhotos: canManage,
      onChanged: () => started = true,
    ),
  );
  return closed == true || started;
}

/// US-14 : affectation à un technicien (responsable). Charge les techniciens si besoin.
/// Renvoie true si l'intervention a été affectée.
Future<bool> assignIntervention(
  BuildContext context,
  ApiClient apiClient,
  Map<String, dynamic> item, {
  List<Map<String, dynamic>>? technicians,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void show(String m) => messenger?.showSnackBar(SnackBar(content: Text(m)));
  var list = technicians ?? const <Map<String, dynamic>>[];
  try {
    if (list.isEmpty) {
      final r = await apiClient.request(
        'GET',
        '/techniciens',
        query: {'statut': 'ACTIF'},
      );
      list = r is List
          ? r.whereType<Map<String, dynamic>>().toList()
          : const [];
    }
  } catch (error) {
    show(error is ApiException ? error.message : 'Techniciens indisponibles.');
    return false;
  }
  if (!context.mounted) return false;
  final active = list
      .where((t) => t['statut'] == null || t['statut'] == 'ACTIF')
      .toList();
  if (active.isEmpty) {
    show('Aucun technicien actif : créez-en un dans « Plus » → Techniciens.');
    return false;
  }
  final payload = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _AssignInterventionDialog(
      technicians: active,
      initialPriority: item['priorite']?.toString() ?? 'MOYENNE',
    ),
  );
  if (payload == null || !context.mounted) return false;
  try {
    final result = await apiClient.request(
      'PATCH',
      '/interventions/${item['id']}/affecter',
      body: payload,
    );
    final warnings = result is Map
        ? (result['avertissements'] as List?)?.whereType<String>().toList() ??
              const <String>[]
        : const <String>[];
    if (!context.mounted) return true;
    if (warnings.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Affectation avec avertissement'),
          content: Text(warnings.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Compris'),
            ),
          ],
        ),
      );
    } else {
      show('Intervention affectée.');
    }
    return true;
  } catch (error) {
    show(error is ApiException ? error.message : 'Affectation impossible.');
    return false;
  }
}

/// Extension de US-26 : le technicien prend lui-même une intervention non affectée.
Future<bool> takeIntervention(
  BuildContext context,
  ApiClient apiClient,
  Map<String, dynamic> item,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await apiClient.request(
      'PATCH',
      '/interventions/${item['id']}/prendre-en-charge',
    );
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'Intervention prise en charge : elle est dans « Mes interventions ».',
        ),
      ),
    );
    return true;
  } catch (error) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error is ApiException ? error.message : 'Prise en charge impossible.',
        ),
      ),
    );
    return false;
  }
}
