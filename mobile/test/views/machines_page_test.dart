import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_predictive_mobile/services/api_client.dart';
import 'package:maintenance_predictive_mobile/views/machines/machines_page.dart';

void main() {
  testWidgets('enregistre un seuil sans erreur Flutter', (
    WidgetTester tester,
  ) async {
    final apiClient = _FakeApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: MachineDetailPage(
          apiClient: apiClient,
          machineId: 'machine-1',
          canManageThresholds: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Configurer les seuils'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '35');
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(apiClient.savedThresholds, isTrue);
    expect(find.text('Seuils mis à jour.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    apiClient.dispose();
  });
}

class _FakeApiClient extends ApiClient {
  bool savedThresholds = false;
  double alertThreshold = 30;
  double criticalThreshold = 40;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    if (method == 'PUT' && path.endsWith('/seuils/TEMP')) {
      savedThresholds = true;
      alertThreshold = body!['seuilAlerte'] as double;
      criticalThreshold = body['seuilCritique'] as double;
      return {};
    }
    if (path == '/machines/machine-1') {
      return {
        'nom': 'Moteur 1',
        'code': 'M-001',
        'emplacement': 'Atelier',
        'etat': 'NORMAL',
        'capteurs': [
          {
            'type': 'TEMP',
            'identifiant': 'capteur-1',
            'enLigne': true,
            'derniereValeur': 25,
            'derniereMesureAt': '2026-11-11T10:00:00Z',
            'unite': '°C',
          },
        ],
        'seuils': [
          {
            'typeMesure': 'TEMP',
            'seuilAlerte': alertThreshold,
            'seuilCritique': criticalThreshold,
          },
        ],
      };
    }
    if (path.endsWith('/mesures') || path.endsWith('/historique')) return [];
    throw StateError('Requête inattendue : $method $path');
  }
}
