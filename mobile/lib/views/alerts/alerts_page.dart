import 'dart:async';
import '../shared/live_reload.dart';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../release3/machine_actions.dart';
import '../../theme/app_theme.dart';
import '../common.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({
    super.key,
    required this.apiClient,
    required this.canCloseAlerts,
    this.canAcknowledge = true,
  });

  final ApiClient apiClient;
  final bool canCloseAlerts;
  // Le directeur consulte seulement : l'API refuse sa prise en compte (US-03 : responsable ou technicien)
  final bool canAcknowledge;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> with LiveReload<AlertsPage> {
  List<Map<String, dynamic>> _alerts = const [];
  List<Map<String, dynamic>> _machines = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _status;
  String? _level;
  String? _machineId;
  String _period = '30';
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
      final now = DateTime.now().toUtc();
      final from = now.subtract(Duration(days: int.parse(_period)));
      final query = <String, String>{
        'from': from.toIso8601String(),
        'to': now.toIso8601String(),
        'statut': ?_status,
        'niveau': ?_level,
        'machineId': ?_machineId,
        'limit': '200',
      };
      final results = await Future.wait<dynamic>([
        widget.apiClient.request('GET', '/alertes', query: query),
        widget.apiClient.request('GET', '/machines'),
      ]);
      if (!mounted) return;
      setState(() {
        _alerts = _asList(results[0]);
        _machines = _asList(results[1]);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ApiException
            ? error.message
            : 'Impossible de charger les alertes.';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _asList(dynamic data) =>
      data is List ? data.whereType<Map<String, dynamic>>().toList() : const [];

  Future<void> _acknowledge(Map<String, dynamic> alert) async {
    try {
      await widget.apiClient.request(
        'PATCH',
        '/alertes/${alert['id']}/prise-en-compte',
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alerte prise en compte.')),
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _close(Map<String, dynamic> alert) async {
    final controller = TextEditingController();
    final comment = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clôturer l’alerte'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Commentaire obligatoire',
            hintText: 'Décrivez la résolution de l’alerte',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length < 3) return;
              Navigator.pop(context, value);
            },
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (comment == null || !mounted) return;
    try {
      await widget.apiClient.request(
        'PATCH',
        '/alertes/${alert['id']}/cloture',
        body: {'commentaire': comment},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Alerte clôturée.')));
      }
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is ApiException
        ? error.message
        : 'L’action n’a pas pu être effectuée.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDetails(Map<String, dynamic> alert) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        '${alert['typeMesure'] ?? 'Alerte'} · ${alert['machineCode'] ?? ''}',
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailLine('Machine', alert['machineNom']),
            _DetailLine('Capteur', alert['capteur']),
            _DetailLine('Niveau', alert['niveau']),
            _DetailLine(
              'Mesure',
              '${alert['valeur'] ?? '—'} ${alert['unite'] ?? ''}',
            ),
            _DetailLine(
              'Seuil dépassé',
              '${alert['seuilDepasse'] ?? '—'} ${alert['unite'] ?? ''}',
            ),
            _DetailLine('Détectée le', _formatDate(alert['createdAt'])),
            _DetailLine(
              'Délai de détection',
              _detectionDelay(alert['delaiDetectionS']),
            ),
            if (alert['commentaire'] != null)
              _DetailLine('Commentaire', alert['commentaire']),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final delays = _alerts
        .map((alert) => alert['delaiDetectionS'])
        .whereType<num>()
        .toList();
    final averageDelay = delays.isEmpty
        ? null
        : delays.reduce((a, b) => a + b) / delays.length;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _filters(),
                const SizedBox(height: 12),
                if (!_isLoading && _errorMessage == null)
                  AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.speed_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            averageDelay == null
                                ? '${_alerts.length} alerte(s) · délai de détection indisponible'
                                : '${_alerts.length} alerte(s) · délai moyen de détection : '
                                      '${_detectionDelay(averageDelay)}',
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 28),
                    child: Center(child: CircularProgressIndicator()),
                  ),
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
                if (!_isLoading && _errorMessage == null && _alerts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: Center(
                      child: Text('Aucune alerte pour ces filtres.'),
                    ),
                  ),
                ..._alerts.map(_alertCard),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _filters() => AppCard(
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Filtres des alertes',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            IconButton(
              tooltip: 'Actualiser les alertes',
              onPressed: _isLoading ? null : _load,
              visualDensity: VisualDensity.compact,
              color: AppColors.steel,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: _period,
          decoration: const InputDecoration(
            labelText: 'Période',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: '1', child: Text('24 dernières heures')),
            DropdownMenuItem(value: '7', child: Text('7 derniers jours')),
            DropdownMenuItem(value: '30', child: Text('30 derniers jours')),
            DropdownMenuItem(value: '90', child: Text('90 derniers jours')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _period = value);
            _load();
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: _status,
          decoration: const InputDecoration(
            labelText: 'Statut',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: null, child: Text('Tous les statuts')),
            DropdownMenuItem(value: 'OUVERTE', child: Text('Ouverte')),
            DropdownMenuItem(
              value: 'PRISE_EN_COMPTE',
              child: Text('Prise en compte'),
            ),
            DropdownMenuItem(value: 'CLOTUREE', child: Text('Clôturée')),
          ],
          onChanged: (value) {
            setState(() => _status = value);
            _load();
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: _level,
          decoration: const InputDecoration(
            labelText: 'Niveau',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: null, child: Text('Tous les niveaux')),
            DropdownMenuItem(value: 'ALERTE', child: Text('Alerte')),
            DropdownMenuItem(value: 'CRITIQUE', child: Text('Critique')),
          ],
          onChanged: (value) {
            setState(() => _level = value);
            _load();
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: _machineId,
          decoration: const InputDecoration(
            labelText: 'Machine',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Toutes les machines'),
            ),
            ..._machines.map(
              (machine) => DropdownMenuItem(
                value: machine['id']?.toString(),
                child: Text(
                  '${machine['code'] ?? ''} · ${machine['nom'] ?? 'Machine'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() => _machineId = value);
            _load();
          },
        ),
      ],
    ),
  );

  Widget _alertCard(Map<String, dynamic> alert) {
    final status = alert['statut']?.toString() ?? 'INCONNU';
    final critical = alert['niveau'] == 'CRITIQUE';
    final isOpen = status == 'OUVERTE';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  critical ? Icons.error_outline : Icons.warning_amber,
                  color: critical ? Colors.red : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${alert['typeMesure'] ?? 'Alerte'} · '
                        '${alert['machineCode'] ?? 'Machine'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${alert['machineNom'] ?? ''} · '
                        '${alert['valeur'] ?? '—'} ${alert['unite'] ?? ''} '
                        '(seuil ${alert['seuilDepasse'] ?? '—'})',
                      ),
                      Text(
                        '${_formatDate(alert['createdAt'])} · '
                        'Détection ${_detectionDelay(alert['delaiDetectionS'])}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  critical ? 'Critique' : 'Alerte',
                  critical ? Tone.danger : Tone.warn,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip(
                  _statusLabel(status),
                  status == 'CLOTUREE'
                      ? Tone.ok
                      : status == 'PRISE_EN_COMPTE'
                      ? Tone.info
                      : Tone.neutral,
                ),
                TextButton(
                  onPressed: () => _showDetails(alert),
                  child: const Text('Détail'),
                ),
                if (isOpen && widget.canAcknowledge)
                  OutlinedButton(
                    onPressed: () => _acknowledge(alert),
                    child: const Text('Prendre en compte'),
                  ),
                if (widget.canCloseAlerts && status != 'CLOTUREE')
                  FilledButton.tonal(
                    onPressed: () => _close(alert),
                    child: const Text('Clôturer'),
                  ),
                // US-13 : le responsable planifie la réparation depuis l'alerte (le technicien la réalise)
                if (widget.canCloseAlerts && status != 'CLOTUREE')
                  OutlinedButton(
                    onPressed: () async {
                      if (await showPlanFromAlertDialog(
                        context,
                        widget.apiClient,
                        alert,
                      )) {
                        _load();
                      }
                    },
                    child: const Text('Planifier une intervention'),
                  ),
                if (widget.canCloseAlerts && alert['fausseAlerte'] != true)
                  TextButton(
                    onPressed: () async {
                      if (await showFalseAlarmDialog(
                        context,
                        widget.apiClient,
                        alert,
                      )) {
                        _load();
                      }
                    },
                    child: const Text('Fausse alerte'),
                  ),
                if (alert['fausseAlerte'] == true)
                  const StatusChip('Fausse alerte', Tone.neutral),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'OUVERTE' => 'Ouverte',
    'PRISE_EN_COMPTE' => 'Prise en compte',
    'CLOTUREE' => 'Clôturée',
    _ => status,
  };

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Date inconnue';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} à $hour:$minute';
  }

  String _detectionDelay(dynamic value) {
    if (value is! num) return 'indisponible';
    return value < 1
        ? '${(value * 1000).round()} ms'
        : '${value.toStringAsFixed(1)} s';
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text('$label : ${value ?? '—'}'),
  );
}
