import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_predictive_mobile/models/app_role.dart';
import 'package:maintenance_predictive_mobile/services/api_client.dart';
import 'package:maintenance_predictive_mobile/views/alerts/alerts_page.dart';
import 'package:maintenance_predictive_mobile/views/home/main_shell.dart';
import 'package:maintenance_predictive_mobile/views/shared/measure_chart.dart';

// Corrections de la vérification de la Release 2 (application mobile)
void main() {
  group('US-04 courbe des mesures', () {
    test('l’axe vertical englobe les mesures et les seuils', () {
      final (lo, hi) = MeasureChartPainter.range([2, 3, 4], [5, 8]);
      expect(lo, lessThan(2));
      expect(hi, greaterThan(8));
      final (flatLo, flatHi) = MeasureChartPainter.range([3, 3], [null]);
      expect(
        flatHi - flatLo,
        greaterThan(1),
      ); // série constante : pas de division par zéro
    });

    testWidgets(
      'trace la courbe avec ses seuils, message si trop peu de points',
      (tester) async {
        final t = DateTime.utc(2026, 11, 12, 10);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MeasureChart(
                points: [
                  for (var i = 0; i < 20; i++)
                    MeasurePoint(t.add(Duration(seconds: 5 * i)), 20 + i / 2),
                ],
                alertThreshold: 45,
                criticalThreshold: 60,
                unit: '°C',
              ),
            ),
          ),
        );
        expect(find.byType(CustomPaint), findsWidgets);
        expect(
          find.bySemanticsLabel(RegExp('Courbe de 20 mesures')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MeasureChart(points: [MeasurePoint(t, 1)])),
          ),
        );
        expect(find.textContaining('Pas assez de mesures'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'le directeur ne voit pas « Prendre en compte » (refusé par l’API)',
    (tester) async {
      final api = _FakeApi();
      for (final (canAck, expected) in [
        (false, findsNothing),
        (true, findsOneWidget),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AlertsPage(
                key: UniqueKey(),
                apiClient: api,
                canCloseAlerts: false,
                canAcknowledge: canAck,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Prendre en compte'), expected);
      }
    },
  );

  testWidgets(
    'le badge de l’onglet Alertes affiche le nombre réel d’alertes ouvertes',
    (tester) async {
      Future<void> pump(int openAlerts) => tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            apiClient: _FakeApi(),
            role: AppRole.chefProduction,
            notificationCount: 0,
            openAlerts: openAlerts,
            onNotificationsOpened: () {},
          ),
        ),
      );
      await pump(0);
      await tester.pump();
      expect(find.text('3'), findsNothing);
      await pump(7);
      await tester.pump();
      expect(find.text('7'), findsWidgets);
    },
  );
}

class _FakeApi extends ApiClient {
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    if (path == '/alertes') {
      return [
        {
          'id': 1,
          'machineId': 1,
          'machineCode': 'M01',
          'machineNom': 'Presse',
          'typeMesure': 'VIBRATION',
          'unite': 'imp/s',
          'niveau': 'ALERTE',
          'valeur': 30,
          'seuilDepasse': 20,
          'statut': 'OUVERTE',
          'createdAt': '2026-11-12T10:00:00Z',
          'delaiDetectionS': 0.2,
        },
      ];
    }
    if (path == '/indicateurs/dashboard') return <String, dynamic>{};
    return [];
  }
}
