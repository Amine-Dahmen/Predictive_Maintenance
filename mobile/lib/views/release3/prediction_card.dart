import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../common.dart';
import '../shared/measure_chart.dart';

/// US-22 (bonus) : probabilité de panne dans les 48 h calculée par le modèle d'IA.
class PredictionCard extends StatefulWidget {
  const PredictionCard({
    super.key,
    required this.apiClient,
    required this.machineId,
  });

  final ApiClient apiClient;
  final int machineId;

  @override
  State<PredictionCard> createState() => _PredictionCardState();
}

class _PredictionCardState extends State<PredictionCard> {
  List<Map<String, dynamic>> _history = const [];
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.apiClient.request(
        'GET',
        '/predictions/machines/${widget.machineId}',
      );
      if (!mounted) return;
      setState(() {
        _history = (r as List).whereType<Map<String, dynamic>>().toList();
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  static Tone tone(String niveau) => switch (niveau) {
    'ELEVE' => Tone.danger,
    'MOYEN' => Tone.warn,
    'FAIBLE' => Tone.ok,
    _ => Tone.neutral,
  };

  static String label(String niveau) => switch (niveau) {
    'ELEVE' => 'Risque élevé',
    'MOYEN' => 'Risque moyen',
    'FAIBLE' => 'Risque faible',
    _ => 'Historique insuffisant',
  };

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_history.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'Prédiction de panne : pas encore calculée.',
          style: TextStyle(fontSize: 12),
        ),
      );
    }
    final last = _history.last;
    final niveau = last['niveau']?.toString() ?? 'INCONNU';
    final p = last['probabilite'];
    final factors = (last['facteurs'] as List? ?? const []).whereType<Map>();
    final points = [
      for (final h in _history)
        if (h['probabilite'] is num &&
            DateTime.tryParse('${h['createdAt']}') != null)
          MeasurePoint(
            DateTime.parse('${h['createdAt']}'),
            (h['probabilite'] as num) * 100,
          ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p is num
                        ? 'Panne dans les 48 h : ${(p * 100).toStringAsFixed(0)} %'
                        : 'Prédiction de panne',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(label(niveau), tone(niveau)),
              ],
            ),
            if (factors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Facteur principal : ${factors.first['libelle']}'),
              ),
            if (points.length >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MeasureChart(
                  points: points,
                  unit: '%',
                  alertThreshold: 10,
                  criticalThreshold: 20,
                  gap: const Duration(minutes: 30),
                ),
              ),
            const Text(
              'Estimation du modèle d’IA à partir de l’écart des capteurs à leur comportement habituel. '
              'À confirmer par une inspection.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
