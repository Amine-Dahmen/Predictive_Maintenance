import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../common.dart';
import '../shared/measure_chart.dart';

/// US-32 : comparaison de plusieurs machines (mesures, alertes, disponibilité).
class ComparisonPage extends StatefulWidget {
  const ComparisonPage({
    super.key,
    required this.apiClient,
    required this.machines,
  });

  final ApiClient apiClient;
  final List<Map<String, dynamic>> machines;

  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends State<ComparisonPage> {
  late final Set<int> _ids = widget.machines
      .take(2)
      .map((m) => m['id'] as int)
      .toSet();
  String _type = 'VIBRATION';
  int _days = 7;
  Map<String, dynamic>? _result;
  String? _error;
  bool _loading = false;

  static const types = {
    'COURANT': 'Courant',
    'VIBRATION': 'Vibration',
    'TEMPERATURE': 'Température',
    'HUMIDITE': 'Humidité',
  };

  @override
  void initState() {
    super.initState();
    if (_ids.length >= 2) _load();
  }

  Future<void> _load() async {
    if (_ids.length < 2) {
      setState(() => _error = 'Choisissez au moins 2 machines.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now().toUtc();
      final r = await widget.apiClient.request(
        'GET',
        '/machines/comparaison',
        query: {
          'ids': _ids.join(','),
          'type': _type,
          'from': now.subtract(Duration(days: _days)).toIso8601String(),
          'to': now.toIso8601String(),
        },
      );
      if (mounted) setState(() => _result = r as Map<String, dynamic>);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Comparaison impossible.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _n(dynamic v, [int d = 1]) => v is num ? v.toStringAsFixed(d) : '—';

  @override
  Widget build(BuildContext context) {
    final machines = ((_result?['machines'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Comparer des machines')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final m in widget.machines)
                FilterChip(
                  label: Text(m['code'].toString()),
                  selected: _ids.contains(m['id']),
                  onSelected: (on) {
                    setState(
                      () =>
                          on ? _ids.add(m['id'] as int) : _ids.remove(m['id']),
                    );
                    _load();
                  },
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Mesure'),
                  items: [
                    for (final e in types.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    setState(() => _type = v ?? _type);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _days,
                  decoration: const InputDecoration(labelText: 'Période'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('24 h')),
                    DropdownMenuItem(value: 7, child: Text('7 jours')),
                    DropdownMenuItem(value: 30, child: Text('30 jours')),
                  ],
                  onChanged: (v) {
                    setState(() => _days = v ?? _days);
                    _load();
                  },
                ),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final m in machines) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${m['code']} · ${m['nom']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ..._stats(m),
                  Text(
                    'Alertes : ${m['alertes']?['total'] ?? 0} (dont ${m['alertes']?['critiques'] ?? 0} critiques) · '
                    'Pannes : ${m['indicateurs']?['nbPannes'] ?? 0} · '
                    'Disponibilité : ${m['indicateurs']?['disponibilite'] is num ? '${(m['indicateurs']['disponibilite'] * 100).toStringAsFixed(1)} %' : '—'}',
                  ),
                  const SizedBox(height: 8),
                  MeasureChart(
                    points: [
                      for (final p in (m['serie'] as List? ?? const []))
                        if (p is Map &&
                            p['v'] is num &&
                            DateTime.tryParse('${p['t']}') != null)
                          MeasurePoint(
                            DateTime.parse('${p['t']}'),
                            (p['v'] as num).toDouble(),
                          ),
                    ],
                    gap: Duration(
                      seconds: ((_result?['pasS'] as num?) ?? 60).toInt() * 3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _stats(Map<String, dynamic> m) {
    final stats = (m['mesures'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    if (stats.isEmpty) return [const Text('Aucune mesure sur la période.')];
    final s = stats.first;
    return [
      Text(
        'Moyenne ${_n(s['moyenne'])} · min ${_n(s['minimum'])} · max ${_n(s['maximum'])} '
        '· écart-type ${_n(s['ecartType'], 2)} (${s['nb']} mesures)',
      ),
    ];
  }
}
