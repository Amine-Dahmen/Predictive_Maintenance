import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_predictive_mobile/services/api_client.dart';
import 'package:maintenance_predictive_mobile/services/realtime_notifications_service.dart';
import 'package:maintenance_predictive_mobile/views/machines/machines_page.dart';
import 'package:maintenance_predictive_mobile/views/operations/interventions_page.dart';

/// Faux backend : une machine M01 en panne, une réparation curative (statut modifiable).
class _Backend extends ApiClient {
  _Backend({
    this.status = 'AFFECTEE',
    this.assigned = true,
    this.technician = false,
  });

  String status;
  bool assigned;
  // technicien : le serveur ne renvoie que ses interventions (les autres via « À prendre »)
  final bool technician;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>?>{};

  Map<String, dynamic> get intervention => {
    'id': 1,
    'type': 'CURATIVE',
    'statut': status,
    'priorite': 'URGENTE',
    'machineId': 1,
    'machineCode': 'M01',
    'machineNom': 'Presse',
    'description': 'Panne déclarée : moteur',
    'technicienId': assigned ? 3 : null,
    'technicienPrenom': assigned ? 'Ali' : null,
    'technicienNom': assigned ? 'Ben' : null,
  };

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    calls.add('$method $path');
    bodies['$method $path'] = body;
    if (method == 'PATCH' && path.endsWith('/demarrer')) status = 'EN_COURS';
    if (method == 'PATCH' && path.endsWith('/cloturer')) status = 'CLOTUREE';
    if (path == '/interventions') {
      if (query?['aPrendre'] == 'true') return assigned ? [] : [intervention];
      return assigned || !technician ? [intervention] : [];
    }
    if (method == 'PATCH' && path.endsWith('/prendre-en-charge')) {
      assigned = true;
      status = 'AFFECTEE';
      return intervention;
    }
    if (path == '/interventions/1')
      return {...intervention, 'compteRendu': null};
    if (path.endsWith('/photos')) return [];
    if (path == '/machines/1') {
      return {
        'id': 1,
        'code': 'M01',
        'nom': 'Presse',
        'etat': 'PANNE',
        'capteurs': [],
        'seuils': [],
      };
    }
    if (path.startsWith('/predictions')) return [];
    return path.endsWith('mesures') ||
            path.endsWith('historique') ||
            path == '/machines' ||
            path == '/techniciens'
        ? []
        : {};
  }
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(MaterialApp(home: w));
  await tester.pumpAndSettle();
}

void main() {
  test('une notification par carte et par changement d’état', () {
    final t = BoardStatusTracker();
    expect(
      t.shouldNotify({'machineId': 1, 'enLigne': true}),
      isFalse,
    ); // état initial connu
    expect(t.shouldNotify({'machineId': 1, 'enLigne': false}), isTrue);
    expect(
      t.shouldNotify({'machineId': 1, 'enLigne': false}),
      isFalse,
    ); // répétition
    expect(t.shouldNotify({'machineId': 1, 'enLigne': true}), isTrue);
    expect(t.shouldNotify({'machineId': 1, 'enLigne': true}), isFalse);
    expect(t.shouldNotify({'machineId': 2, 'enLigne': false}), isTrue);
  });

  testWidgets(
    'directeur : la liste des interventions s’affiche (plantait avant)',
    (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: InterventionsPage(
            apiClient: _Backend(),
            isTechnician: false,
            canManage: false,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Panne déclarée : moteur'), findsOneWidget);
      expect(find.text('Affecter'), findsNothing);
    },
  );

  testWidgets(
    'technicien : démarrer, rédiger et clôturer la réparation depuis le détail',
    (tester) async {
      final api = _Backend();
      var changed = false;
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => changed = await openInterventionDetail(
                context,
                apiClient: api,
                intervention: api.intervention,
                isTechnician: true,
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Démarrez l’intervention'), findsOneWidget);
      await tester.tap(find.text('Démarrer l’intervention'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('PATCH /interventions/1/demarrer'));
      expect(
        find.text('Statut : En cours'),
        findsOneWidget,
      ); // statut relu depuis l'API
      await tester.enterText(
        find.widgetWithText(TextField, 'Diagnostic'),
        'Roulement grippé',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Actions réalisées'),
        'Roulement remplacé',
      );
      await tester.ensureVisible(find.text('Clôturer l’intervention'));
      await tester.tap(find.text('Clôturer l’intervention'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Machine remise en service'));
      await tester.pumpAndSettle();
      expect(
        api.bodies['PUT /interventions/1/compte-rendu']?['diagnostic'],
        'Roulement grippé',
      );
      expect(api.bodies['PATCH /interventions/1/cloturer'], {
        'resultat': 'REMISE_EN_SERVICE',
      });
      expect(changed, isTrue);
    },
  );

  testWidgets(
    'technicien : pas de déclaration de panne, explication si la réparation n’est pas affectée',
    (tester) async {
      final api = _Backend(status: 'A_AFFECTER', assigned: false);
      // le serveur ne renvoie au technicien que SES interventions : aucune ici
      final tech = _TechView(api);
      await _pump(
        tester,
        MachineDetailPage(
          apiClient: tech,
          machineId: '1',
          canManageThresholds: false,
          canOperate: true,
        ),
      );
      expect(find.byTooltip('Déclarer une panne'), findsNothing);
      expect(find.byTooltip('Comparer des machines'), findsNothing);
      expect(find.textContaining('prenez la panne en charge'), findsOneWidget);
      expect(find.text('Prendre en charge la panne'), findsOneWidget);
    },
  );

  testWidgets(
    'responsable : déclare la panne et voit la réparation à affecter sur la fiche',
    (tester) async {
      final api = _Backend(status: 'A_AFFECTER', assigned: false);
      await _pump(
        tester,
        MachineDetailPage(
          apiClient: api,
          machineId: '1',
          canManageThresholds: true,
          canOperate: true,
        ),
      );
      expect(find.byTooltip('Déclarer une panne'), findsOneWidget);
      expect(find.text('Interventions en cours'), findsOneWidget);
      expect(find.byTooltip('Affecter'), findsOneWidget);
      expect(find.textContaining('remise en service'), findsOneWidget);
    },
  );

  testWidgets(
    'les pages se rechargent quand le serveur annonce un changement (web et mobile synchronisés)',
    (tester) async {
      final api = _Backend();
      await _pump(
        tester,
        Scaffold(
          body: MachinesPage(apiClient: api, canManageThresholds: false),
        ),
      );
      final before = api.calls.where((c) => c == 'GET /machines').length;
      api.announceChange(
        'mesure.recue',
      ); // trop fréquent : ne recharge pas la liste
      await tester.pump(const Duration(seconds: 2));
      expect(api.calls.where((c) => c == 'GET /machines').length, before);
      api.announceChange('machine.etat');
      api.announceChange('alerte.creee'); // rafale : un seul rechargement
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c == 'GET /machines').length, before + 1);
    },
  );

  testWidgets(
    'technicien : « À prendre » puis « Prendre en charge » (sans attendre le responsable)',
    (tester) async {
      final api = _Backend(
        status: 'A_AFFECTER',
        assigned: false,
        technician: true,
      );
      await _pump(
        tester,
        Scaffold(
          body: InterventionsPage(
            apiClient: api,
            isTechnician: true,
            canManage: false,
          ),
        ),
      );
      expect(
        find.text('Aucune intervention trouvée.'),
        findsOneWidget,
      ); // rien d'affecté pour l'instant
      await tester.tap(find.text('À prendre'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Panne déclarée : moteur'), findsOneWidget);
      await tester.tap(find.text('Prendre en charge'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('PATCH /interventions/1/prendre-en-charge'));
      expect(
        find.text('Démarrer'),
        findsOneWidget,
      ); // retour à « Mes interventions », prête à démarrer
    },
  );
}

class _TechView extends _Backend {
  _TechView(_Backend b) : super(status: b.status, assigned: b.assigned);

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    if (path == '/interventions')
      return []; // ni affectée ni à prendre : personne n'a la réparation
    return super.request(
      method,
      path,
      body: body,
      query: query,
      allowRefresh: allowRefresh,
    );
  }
}
