import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_predictive_mobile/services/api_client.dart';
import 'package:maintenance_predictive_mobile/views/machines/machines_page.dart';
import 'package:maintenance_predictive_mobile/views/operations/interventions_page.dart';

void main() {
  testWidgets('actualise les machines depuis leur carte de filtres', (
    WidgetTester tester,
  ) async {
    final apiClient = _FakeListApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MachinesPage(apiClient: apiClient, canManageThresholds: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filtres des machines'), findsOneWidget);
    expect(find.byTooltip('Actualiser les machines'), findsOneWidget);
    expect(apiClient.countFor('/machines'), 1);

    await tester.tap(find.byTooltip('Actualiser les machines'));
    await tester.pumpAndSettle();

    expect(apiClient.countFor('/machines'), 2);
    expect(tester.takeException(), isNull);
    apiClient.dispose();
  });

  testWidgets('actualise les interventions depuis leur carte de filtres', (
    WidgetTester tester,
  ) async {
    final apiClient = _FakeListApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InterventionsPage(
            apiClient: apiClient,
            isTechnician: false,
            canManage: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filtres des interventions'), findsOneWidget);
    expect(find.byTooltip('Actualiser les interventions'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(apiClient.countFor('/interventions'), 1);

    await tester.tap(find.byTooltip('Actualiser les interventions'));
    await tester.pumpAndSettle();

    expect(apiClient.countFor('/interventions'), 2);
    expect(tester.takeException(), isNull);
    apiClient.dispose();
  });
}

class _FakeListApiClient extends ApiClient {
  final Map<String, int> _requestCounts = {};

  int countFor(String path) => _requestCounts[path] ?? 0;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    _requestCounts.update(path, (count) => count + 1, ifAbsent: () => 1);
    if (path == '/machines' ||
        path == '/interventions' ||
        path == '/techniciens') {
      return [];
    }
    throw StateError('Requête inattendue : $method $path');
  }
}
