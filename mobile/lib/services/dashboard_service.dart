import 'api_client.dart';

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.metrics,
    required this.statusTitle,
    required this.statusSubtitle,
  });

  final Map<String, int> metrics;
  final String statusTitle;
  final String statusSubtitle;
}

class DashboardService {
  DashboardService(this.client);

  final ApiClient client;

  Future<DashboardSnapshot> loadChefDashboard() async {
    final data =
        await client.request('GET', '/indicateurs/dashboard')
            as Map<String, dynamic>;
    final machines = _map(data['machines']);
    final alertes = _map(data['alertes']);
    final machineStates = _map(machines['parEtat']);

    return DashboardSnapshot(
      metrics: {
        'Total machines': _int(machines['total']),
        'Normales': _int(machineStates['NORMAL']),
        'En alerte': _int(machineStates['ALERTE']),
        'En panne': _int(machineStates['PANNE']),
        'En maintenance': _int(machineStates['EN_MAINTENANCE']),
        'Sans données': _int(machineStates['SANS_DONNEES']),
      },
      statusTitle: alertes['critiques'] == 0
          ? 'Système sous contrôle'
          : 'Alertes critiques à traiter',
      statusSubtitle: alertes['critiques'] == 0
          ? '${_int(alertes['ouvertes'])} alerte(s) ouverte(s). Données issues du backend.'
          : '${_int(alertes['critiques'])} alerte(s) critique(s) nécessite(nt) votre attention.',
    );
  }

  Future<DashboardSnapshot> loadTechnicianDashboard() async {
    final results = await Future.wait<dynamic>([
      client.request('GET', '/machines'),
      client.request('GET', '/alertes'),
      client.request('GET', '/interventions'),
    ]);
    final machines = _list(results[0]);
    final alertes = _list(results[1]);
    final interventions = _list(results[2]);
    final activeAlerts = alertes.where((item) {
      final status = item['statut']?.toString();
      return status != 'CLOTUREE';
    }).length;

    return DashboardSnapshot(
      metrics: {
        'À faire': interventions
            .where(
              (item) =>
                  item['statut'] == 'AFFECTEE' ||
                  item['statut'] == 'A_AFFECTER',
            )
            .length,
        'En cours': interventions
            .where((item) => item['statut'] == 'EN_COURS')
            .length,
        'Terminées': interventions
            .where((item) => item['statut'] == 'CLOTUREE')
            .length,
        'Alertes': activeAlerts,
      },
      statusTitle: activeAlerts == 0
          ? 'Aucune alerte ouverte'
          : '$activeAlerts alerte(s) à surveiller',
      statusSubtitle:
          '${machines.length} machine(s) sont accessibles depuis votre espace.',
    );
  }

  List<Map<String, dynamic>> _list(dynamic data) {
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> _map(dynamic data) =>
      data is Map<String, dynamic> ? data : const {};

  int _int(dynamic value) => value is num ? value.toInt() : 0;
}
