import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_predictive_mobile/services/api_client.dart';
import 'package:maintenance_predictive_mobile/views/alerts/alerts_page.dart';

void main() {
  testWidgets('place le rafraîchissement dans le bloc des filtres', (
    WidgetTester tester,
  ) async {
    final apiClient = _FakeAlertsApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertsPage(apiClient: apiClient, canCloseAlerts: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filtres des alertes'), findsOneWidget);
    expect(find.byTooltip('Actualiser les alertes'), findsOneWidget);
    expect(apiClient.requestCount, 2);

    await tester.tap(find.byTooltip('Actualiser les alertes'));
    await tester.pumpAndSettle();

    expect(apiClient.requestCount, 4);
    expect(tester.takeException(), isNull);
    apiClient.dispose();
  });
}

class _FakeAlertsApiClient extends ApiClient {
  int requestCount = 0;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    requestCount++;
    if (path == '/alertes' || path == '/machines') return [];
    throw StateError('Requête inattendue : $method $path');
  }
}
