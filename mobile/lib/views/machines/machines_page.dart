import 'dart:async';
import '../shared/live_reload.dart';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../shared/measure_chart.dart';
import '../release3/comparison_page.dart';
import '../release3/firmware_page.dart';
import '../release3/machine_actions.dart';
import '../release3/prediction_card.dart';
import '../release3/machine_interventions.dart';
import '../../theme/app_theme.dart';
import '../common.dart';

class MachinesPage extends StatefulWidget {
  const MachinesPage({
    super.key,
    required this.apiClient,
    required this.canManageThresholds,
    this.canOperate = false,
  });

  final ApiClient apiClient;
  final bool canManageThresholds;
  // Technicien et responsable : calibration (US-39) et déclaration de panne (US-29)
  final bool canOperate;

  @override
  State<MachinesPage> createState() => _MachinesPageState();
}

class _MachinesPageState extends State<MachinesPage>
    with LiveReload<MachinesPage> {
  List<Map<String, dynamic>> _machines = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _state;
  String _search = '';
  Timer? _refreshTimer;

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
      final search = _search.trim();
      final result = await widget.apiClient.request(
        'GET',
        '/machines',
        query: {
          'etat': ?_state,
          'recherche': ?(search.isEmpty ? null : search),
        },
      );
      if (!mounted) return;
      setState(() {
        _machines = result is List
            ? result.whereType<Map<String, dynamic>>().toList()
            : const [];
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de charger les machines.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filtres des machines',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (!(widget.canOperate && !widget.canManageThresholds))
                    IconButton(
                      tooltip: 'Comparer des machines',
                      onPressed: _machines.length < 2
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ComparisonPage(
                                  apiClient: widget.apiClient,
                                  machines: _machines,
                                ),
                              ),
                            ),
                      visualDensity: VisualDensity.compact,
                      color: AppColors.steel,
                      icon: const Icon(Icons.compare_arrows),
                    ),
                  IconButton(
                    tooltip: 'Actualiser les machines',
                    onPressed: _isLoading ? null : _load,
                    visualDensity: VisualDensity.compact,
                    color: AppColors.steel,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Rechercher une machine',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          onPressed: () {
                            setState(() => _search = '');
                            _load();
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => _search = value,
                onSubmitted: (_) => _load(),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _state,
                decoration: const InputDecoration(
                  labelText: 'État',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Tous les états')),
                  DropdownMenuItem(value: 'NORMAL', child: Text('Normal')),
                  DropdownMenuItem(value: 'ALERTE', child: Text('Alerte')),
                  DropdownMenuItem(value: 'PANNE', child: Text('Panne')),
                  DropdownMenuItem(
                    value: 'EN_MAINTENANCE',
                    child: Text('En maintenance'),
                  ),
                  DropdownMenuItem(
                    value: 'SANS_DONNEES',
                    child: Text('Sans données'),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _state = value);
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              if (_isLoading) const LinearProgressIndicator(),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
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
              if (!_isLoading && _errorMessage == null && _machines.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(child: Text('Aucune machine trouvée.')),
                ),
              ..._machines.map(_machineCard),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _machineCard(Map<String, dynamic> machine) {
    final state = machine['etat']?.toString() ?? 'SANS_DONNEES';
    final count = machine['nbCapteurs'] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MachineDetailPage(
              apiClient: widget.apiClient,
              machineId: machine['id'].toString(),
              canManageThresholds: widget.canManageThresholds,
              canOperate: widget.canOperate,
            ),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _stateColor(state).withAlpha(25),
              child: Icon(
                Icons.precision_manufacturing_outlined,
                color: _stateColor(state),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${machine['code'] ?? ''} · ${machine['nom'] ?? 'Machine'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${machine['emplacement'] ?? 'Emplacement non défini'} · '
                    '$count capteur(s)',
                  ),
                  const SizedBox(height: 5),
                  StatusChip(_stateLabel(state), _stateTone(state)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class MachineDetailPage extends StatefulWidget {
  const MachineDetailPage({
    super.key,
    required this.apiClient,
    required this.machineId,
    required this.canManageThresholds,
    this.canOperate = false,
  });

  final ApiClient apiClient;
  final String machineId;
  final bool canManageThresholds;
  final bool canOperate;

  @override
  State<MachineDetailPage> createState() => _MachineDetailPageState();
}

class _MachineDetailPageState extends State<MachineDetailPage>
    with LiveReload<MachineDetailPage> {
  Map<String, dynamic>? _machine;
  List<Map<String, dynamic>> _measurements = const [];
  List<Map<String, dynamic>> _history = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _failuresOnly = false;
  String? _errorMessage;
  String? _sensorType;
  int _reloads =
      0; // recharge les cartes de la fiche (interventions) à chaque actualisation
  String _period = '7';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    liveReload(
      widget.apiClient,
      () => _load(silent: true),
      types: {...LiveReload.defaultTypes, 'mesure.'},
      debounce: const Duration(seconds: 3),
    );
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isLoading && !_isSaving) _load();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // silent : rechargement en direct (nouvelle mesure, changement d'état) sans barre de chargement
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final now = DateTime.now().toUtc();
      final from = now.subtract(Duration(days: int.parse(_period)));
      final dateQuery = {
        'from': from.toIso8601String(),
        'to': now.toIso8601String(),
      };
      final results = await Future.wait<dynamic>([
        widget.apiClient.request('GET', '/machines/${widget.machineId}'),
        widget.apiClient.request(
          'GET',
          '/machines/${widget.machineId}/mesures',
          query: {...dateQuery, 'type': ?_sensorType, 'limit': '500'},
        ),
        widget.apiClient.request(
          'GET',
          '/machines/${widget.machineId}/historique',
          query: dateQuery,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _machine = results[0] is Map<String, dynamic>
            ? results[0] as Map<String, dynamic>
            : null;
        _measurements = _asList(results[1]);
        _history = _asList(results[2]);
        _isLoading = false;
        _reloads++;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de charger la fiche machine.';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _asList(dynamic data) =>
      data is List ? data.whereType<Map<String, dynamic>>().toList() : const [];

  @override
  Widget build(BuildContext context) {
    final machine = _machine;
    return Scaffold(
      appBar: AppBar(
        title: Text(machine?['nom']?.toString() ?? 'Fiche machine'),
        actions: [
          if (widget.canManageThresholds && machine != null)
            IconButton(
              tooltip: 'Déclarer une panne',
              onPressed: () async {
                if (await showDeclareFailureDialog(
                  context,
                  widget.apiClient,
                  machine['id'] as int,
                )) {
                  _load();
                }
              },
              icon: const Icon(Icons.report_problem_outlined),
            ),
          if (widget.canManageThresholds && machine != null)
            IconButton(
              tooltip: 'Firmware de la carte',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FirmwarePage(
                    apiClient: widget.apiClient,
                    machine: machine,
                  ),
                ),
              ),
              icon: const Icon(Icons.system_update_alt),
            ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading && machine == null
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && machine == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_errorMessage!),
                  TextButton(onPressed: _load, child: const Text('Réessayer')),
                ],
              ),
            )
          : DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  _machineSummary(machine ?? const {}),
                  if (machine?['id'] is int)
                    PredictionCard(
                      apiClient: widget.apiClient,
                      machineId: machine!['id'] as int,
                    ),
                  if (machine?['id'] is int)
                    MachineInterventionsCard(
                      key: ValueKey(
                        'interventions-${machine!['etat']}-$_reloads',
                      ),
                      apiClient: widget.apiClient,
                      machineId: machine['id'] as int,
                      machineState: machine['etat']?.toString() ?? '',
                      isTechnician:
                          widget.canOperate && !widget.canManageThresholds,
                      canManage: widget.canManageThresholds,
                      onChanged: _load,
                    ),
                  const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Capteurs & seuils'),
                      Tab(text: 'Mesures'),
                      Tab(text: 'Historique'),
                    ],
                  ),
                  if (_isLoading) const LinearProgressIndicator(),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _sensorsTab(machine ?? const {}),
                        _measurementsTab,
                        _historyTab,
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _machineSummary(Map<String, dynamic> machine) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: AppCard(
      child: Row(
        children: [
          const Icon(Icons.precision_manufacturing_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${machine['code'] ?? ''} · ${machine['emplacement'] ?? 'Emplacement non défini'}',
                ),
                const SizedBox(height: 5),
                StatusChip(
                  _stateLabel(machine['etat']?.toString() ?? 'INCONNU'),
                  _stateTone(machine['etat']?.toString() ?? 'INCONNU'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sensorsTab(Map<String, dynamic> machine) {
    final sensors = _asList(machine['capteurs']);
    final thresholds = _asList(machine['seuils']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sensors.isEmpty)
          const Text('Aucun capteur associé à cette machine.'),
        ...sensors.map((sensor) {
          final type = sensor['type']?.toString();
          final threshold = thresholds.where(
            (item) => item['typeMesure'] == type,
          );
          final thresholdValue = threshold.isEmpty ? null : threshold.first;
          final online = sensor['enLigne'] == true;
          final retired = sensor['actif'] == false;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sensors,
                        color: online ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${sensor['type'] ?? 'Capteur'} · ${sensor['identifiant'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      StatusChip(
                        retired
                            ? 'Retiré'
                            : online
                            ? 'En ligne'
                            : 'Hors ligne',
                        retired
                            ? Tone.neutral
                            : online
                            ? Tone.ok
                            : Tone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dernière valeur : ${sensor['derniereValeur'] ?? '—'} '
                    '${sensor['unite'] ?? ''}',
                  ),
                  Text(
                    'Dernière mesure : ${_formatDate(sensor['derniereMesureAt'])}',
                  ),
                  if (thresholdValue != null)
                    Text(
                      'Seuils : alerte ${thresholdValue['seuilAlerte']} · '
                      'critique ${thresholdValue['seuilCritique']} ${sensor['unite'] ?? ''}',
                    ),
                  if (sensor['calibreAt'] != null)
                    Text(
                      'Calibration : gain ${sensor['calibrationGain']} · offset ${sensor['calibrationOffset']}',
                    ),
                  if (!retired)
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        if (widget.canManageThresholds)
                          TextButton.icon(
                            onPressed: _isSaving || thresholdValue == null
                                ? null
                                : () => _editThreshold(sensor, thresholdValue),
                            icon: const Icon(Icons.tune),
                            label: const Text('Configurer les seuils'),
                          ),
                        if (widget.canOperate)
                          TextButton.icon(
                            onPressed: () async {
                              if (await showCalibrationDialog(
                                context,
                                widget.apiClient,
                                sensor,
                              )) {
                                _load();
                              }
                            },
                            icon: const Icon(Icons.straighten),
                            label: const Text('Calibrer'),
                          ),
                        if (widget.canManageThresholds)
                          TextButton.icon(
                            onPressed: () async {
                              if (await showReplaceSensorDialog(
                                context,
                                widget.apiClient,
                                sensor,
                              )) {
                                _load();
                              }
                            },
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('Remplacer'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget get _measurementsTab => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _period,
                decoration: const InputDecoration(
                  labelText: 'Période',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: '1', child: Text('24 h')),
                  DropdownMenuItem(value: '7', child: Text('7 jours')),
                  DropdownMenuItem(value: '30', child: Text('30 jours')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _period = value);
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _sensorType,
                decoration: const InputDecoration(
                  labelText: 'Capteur',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Tous')),
                  DropdownMenuItem(value: 'COURANT', child: Text('Courant')),
                  DropdownMenuItem(
                    value: 'VIBRATION',
                    child: Text('Vibration'),
                  ),
                  DropdownMenuItem(
                    value: 'TEMPERATURE',
                    child: Text('Température'),
                  ),
                  DropdownMenuItem(value: 'HUMIDITE', child: Text('Humidité')),
                ],
                onChanged: (value) {
                  setState(() => _sensorType = value);
                  _load();
                },
              ),
            ),
          ],
        ),
      ),
      _chart,
      Expanded(
        child: _measurements.isEmpty
            ? const Center(child: Text('Aucune mesure sur cette période.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _measurements.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final measure = _measurements[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.show_chart),
                    title: Text(
                      '${measure['type'] ?? ''} · ${measure['valeur'] ?? '—'} '
                      '${measure['unite'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${measure['identifiant'] ?? ''} · '
                      '${_formatDate(measure['horodatage'])}',
                    ),
                  );
                },
              ),
      ),
    ],
  );

  // US-04 : courbe du capteur choisi, avec ses seuils
  Widget get _chart {
    final type = _sensorType;
    if (_measurements.isEmpty) return const SizedBox.shrink();
    if (type == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('Choisissez un capteur pour afficher sa courbe.'),
      );
    }
    final seuils = (_machine?['seuils'] as List?) ?? const [];
    final seuil = seuils.whereType<Map<String, dynamic>>().where(
      (s) => s['typeMesure'] == type,
    );
    final points = <MeasurePoint>[
      for (final m in _measurements)
        if (m['valeur'] is num &&
            DateTime.tryParse(m['horodatage']?.toString() ?? '') != null)
          MeasurePoint(
            DateTime.parse(m['horodatage'].toString()),
            (m['valeur'] as num).toDouble(),
          ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: MeasureChart(
        points: points,
        unit: _measurements.first['unite']?.toString() ?? '',
        alertThreshold: seuil.isEmpty
            ? null
            : (seuil.first['seuilAlerte'] as num?)?.toDouble(),
        criticalThreshold: seuil.isEmpty
            ? null
            : (seuil.first['seuilCritique'] as num?)?.toDouble(),
      ),
    );
  }

  Widget get _historyTab {
    final history = _failuresOnly
        ? _history.where(
            (item) =>
                (item['categorie'] == 'ALERTE' &&
                    item['sous_type'] == 'CRITIQUE') ||
                (item['categorie'] == 'INTERVENTION' &&
                    item['sous_type'] == 'CURATIVE'),
          )
        : _history;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Pannes uniquement'),
          value: _failuresOnly,
          onChanged: (value) => setState(() => _failuresOnly = value),
        ),
        Expanded(
          child: history.isEmpty
              ? const Center(child: Text('Aucun événement sur cette période.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final event = history.elementAt(index);
                    return ListTile(
                      leading: Icon(
                        event['categorie'] == 'ALERTE'
                            ? Icons.warning_amber
                            : Icons.build_outlined,
                      ),
                      title: Text(event['libelle']?.toString() ?? 'Événement'),
                      subtitle: Text(
                        '${event['categorie'] ?? ''} · '
                        '${event['sous_type'] ?? ''} · '
                        '${event['statut'] ?? ''}\n'
                        '${_formatDate(event['date'])}',
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _editThreshold(
    Map<String, dynamic> sensor,
    Map<String, dynamic> threshold,
  ) async {
    final values = await showDialog<(double, double)>(
      context: context,
      builder: (_) => _ThresholdEditorDialog(
        sensorType: sensor['type']?.toString() ?? '',
        unit: sensor['unite']?.toString() ?? '',
        alertThreshold: threshold['seuilAlerte']?.toString() ?? '',
        criticalThreshold: threshold['seuilCritique']?.toString() ?? '',
      ),
    );
    if (values == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await widget.apiClient.request(
        'PUT',
        '/machines/${widget.machineId}/seuils/${sensor['type']}',
        body: {'seuilAlerte': values.$1, 'seuilCritique': values.$2},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Seuils mis à jour.')));
      }
    } catch (error) {
      if (mounted) {
        final message = error is ApiException
            ? error.message
            : 'Impossible de mettre à jour les seuils.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Inconnue';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} à $hour:$minute';
  }
}

class _ThresholdEditorDialog extends StatefulWidget {
  const _ThresholdEditorDialog({
    required this.sensorType,
    required this.unit,
    required this.alertThreshold,
    required this.criticalThreshold,
  });

  final String sensorType;
  final String unit;
  final String alertThreshold;
  final String criticalThreshold;

  @override
  State<_ThresholdEditorDialog> createState() => _ThresholdEditorDialogState();
}

class _ThresholdEditorDialogState extends State<_ThresholdEditorDialog> {
  late final TextEditingController _alertController;
  late final TextEditingController _criticalController;

  @override
  void initState() {
    super.initState();
    _alertController = TextEditingController(text: widget.alertThreshold);
    _criticalController = TextEditingController(text: widget.criticalThreshold);
  }

  @override
  void dispose() {
    _alertController.dispose();
    _criticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Seuils ${widget.sensorType}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _alertController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Seuil d’alerte (${widget.unit})',
          ),
        ),
        TextField(
          controller: _criticalController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Seuil critique (${widget.unit})',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          final alert = double.tryParse(
            _alertController.text.replaceAll(',', '.'),
          );
          final critical = double.tryParse(
            _criticalController.text.replaceAll(',', '.'),
          );
          if (alert == null ||
              critical == null ||
              alert <= 0 ||
              critical <= alert) {
            return;
          }
          Navigator.pop(context, (alert, critical));
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

Color _stateColor(String state) => switch (state) {
  'NORMAL' => Colors.green,
  'ALERTE' => Colors.orange,
  'PANNE' => Colors.red,
  'EN_MAINTENANCE' => Colors.blue,
  _ => Colors.grey,
};

Tone _stateTone(String state) => switch (state) {
  'NORMAL' => Tone.ok,
  'ALERTE' => Tone.warn,
  'PANNE' => Tone.danger,
  'EN_MAINTENANCE' => Tone.info,
  _ => Tone.neutral,
};

String _stateLabel(String state) => switch (state) {
  'NORMAL' => 'Normal',
  'ALERTE' => 'Alerte',
  'PANNE' => 'Panne',
  'EN_MAINTENANCE' => 'En maintenance',
  'SANS_DONNEES' => 'Sans données',
  _ => state,
};
