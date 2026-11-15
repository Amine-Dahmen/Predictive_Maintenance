import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_predictive_mobile/services/api_client.dart';
import 'package:maintenance_predictive_mobile/views/machines/machines_page.dart';
import 'package:maintenance_predictive_mobile/views/release3/comparison_page.dart';
import 'package:maintenance_predictive_mobile/views/release3/machine_actions.dart';
import 'package:maintenance_predictive_mobile/views/release3/offline_banner.dart';
import 'package:maintenance_predictive_mobile/views/release3/prediction_card.dart';

class _Api extends ApiClient {
  final calls = <String>[];
  final bodies = <Map<String, dynamic>?>[];

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    calls.add('$method $path${query == null ? '' : ' ${query['ids'] ?? ''}'}');
    bodies.add(body);
    if (path == '/machines/1') {
      return {
        'id': 1,
        'code': 'M01',
        'nom': 'Presse',
        'etat': 'NORMAL',
        'seuils': [
          {'typeMesure': 'COURANT', 'seuilAlerte': 3, 'seuilCritique': 4.5},
        ],
        'capteurs': [
          {
            'id': 10,
            'identifiant': 'M01-COURANT',
            'type': 'COURANT',
            'unite': 'A',
            'actif': true,
            'enLigne': true,
            'derniereValeur': 0.42,
            'calibrationGain': 1,
            'calibrationOffset': 0,
          },
          {
            'id': 9,
            'identifiant': 'M01-VIBRATION',
            'type': 'VIBRATION',
            'unite': 'imp/s',
            'actif': false,
          },
        ],
      };
    }
    if (path == '/machines/comparaison') {
      return {
        'pasS': 600,
        'machines': [
          for (final code in ['M01', 'M02'])
            {
              'id': code == 'M01' ? 1 : 2,
              'code': code,
              'nom': 'Machine $code',
              'mesures': [
                {
                  'type': 'VIBRATION',
                  'nb': 12,
                  'moyenne': 4.2,
                  'minimum': 1,
                  'maximum': 30,
                  'ecartType': 2.5,
                },
              ],
              'serie': [
                {'t': '2026-11-12T10:00:00Z', 'v': 3},
                {'t': '2026-11-12T10:10:00Z', 'v': 5},
              ],
              'alertes': {'total': 2, 'critiques': 1},
              'indicateurs': {'nbPannes': 1, 'disponibilite': 0.97},
            },
        ],
      };
    }
    return path.endsWith('mesures') || path.endsWith('historique') ? [] : {};
  }
}

Future<void> _open(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'US-39 / US-37 : le technicien calibre mais ne remplace pas, capteur retiré affiché',
    (tester) async {
      final api = _Api();
      await _open(
        tester,
        MachineDetailPage(
          apiClient: api,
          machineId: '1',
          canManageThresholds: false,
          canOperate: true,
        ),
      );
      expect(
        find.text('Calibrer'),
        findsOneWidget,
      ); // le capteur retiré n'a pas d'action
      expect(find.text('Remplacer'), findsNothing);
      expect(find.text('RETIRÉ', skipOffstage: false), findsOneWidget);
      expect(
        find.byTooltip('Déclarer une panne'),
        findsNothing,
      ); // US-29 : responsable uniquement
      expect(find.byTooltip('Firmware de la carte'), findsNothing);

      await tester.tap(find.text('Calibrer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '0');
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      final i = api.calls.indexOf('PATCH /capteurs/10/calibration');
      expect(i, isNonNegative);
      expect(api.bodies[i], {'valeurReference': 0.0});
    },
  );

  testWidgets(
    'US-37 / US-46 : le responsable peut remplacer un capteur et ouvrir le firmware',
    (tester) async {
      await _open(
        tester,
        MachineDetailPage(
          apiClient: _Api(),
          machineId: '1',
          canManageThresholds: true,
          canOperate: true,
        ),
      );
      expect(find.text('Remplacer'), findsOneWidget);
      expect(find.byTooltip('Firmware de la carte'), findsOneWidget);
    },
  );

  testWidgets(
    'US-29 : déclaration de panne envoyée avec description et début',
    (tester) async {
      final api = _Api();
      await _open(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDeclareFailureDialog(context, api, 1),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Déclarer'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('3 caractères minimum'),
        findsOneWidget,
      ); // description obligatoire
      await tester.enterText(find.byType(TextField).first, 'Courroie cassée');
      await tester.tap(find.text('Déclarer'));
      await tester.pumpAndSettle();
      final body = api.bodies[api.calls.indexOf('POST /machines/1/pannes')]!;
      expect(body['description'], 'Courroie cassée');
      expect(body['priorite'], 'URGENTE');
      expect(
        DateTime.parse(
          body['debutPanne'] as String,
        ).isBefore(DateTime.now().toUtc().add(const Duration(seconds: 1))),
        isTrue,
      );
    },
  );

  testWidgets(
    'US-32 : la comparaison affiche les statistiques de chaque machine',
    (tester) async {
      final api = _Api();
      await _open(
        tester,
        ComparisonPage(
          apiClient: api,
          machines: [
            {'id': 1, 'code': 'M01'},
            {'id': 2, 'code': 'M02'},
          ],
        ),
      );
      expect(api.calls, contains('GET /machines/comparaison 1,2'));
      expect(find.textContaining('Moyenne 4.2'), findsNWidgets(2));
      expect(find.textContaining('Disponibilité : 97.0 %'), findsNWidgets(2));
    },
  );

  testWidgets(
    'US-22 : carte de prédiction avec probabilité, niveau et facteur',
    (tester) async {
      await _open(
        tester,
        Scaffold(
          body: PredictionCard(apiClient: _PredictionApi(), machineId: 1),
        ),
      );
      expect(find.text('Panne dans les 48 h : 25 %'), findsOneWidget);
      expect(find.text('RISQUE ÉLEVÉ'), findsOneWidget);
      expect(
        find.textContaining('Facteur principal : Vibration'),
        findsOneWidget,
      );
    },
  );

  testWidgets('US-28 : bandeau hors ligne avec les modifications en attente', (
    tester,
  ) async {
    final api = ApiClient();
    await _open(tester, Scaffold(body: OfflineBanner(apiClient: api)));
    expect(find.byType(Material), findsWidgets);
    expect(find.textContaining('Hors ligne'), findsNothing);
    api.offline.value = true;
    api.pendingWrites.value = 2;
    await tester.pump();
    expect(find.textContaining('Hors ligne'), findsOneWidget);
    expect(find.textContaining('2 modification(s)'), findsOneWidget);
    expect(find.text('Synchroniser'), findsOneWidget);
  });
}

class _PredictionApi extends ApiClient {
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async => [
    for (var i = 0; i < 3; i++)
      {
        'machineId': 1,
        'probabilite': 0.05 + i * 0.1,
        'niveau': i == 2 ? 'ELEVE' : 'FAIBLE',
        'createdAt': DateTime.utc(2026, 11, 12, 10, i * 5).toIso8601String(),
        'facteurs': [
          {
            'canal': 'vibration',
            'ecart': 2.4,
            'libelle': 'Vibration 2.4 écart(s)-type(s) au-dessus de l’habitude',
          },
        ],
      },
  ];
}
