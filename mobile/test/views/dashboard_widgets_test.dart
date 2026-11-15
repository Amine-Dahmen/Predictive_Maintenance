import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_predictive_mobile/models/ui_models.dart';
import 'package:maintenance_predictive_mobile/theme/app_theme.dart';
import 'package:maintenance_predictive_mobile/views/common.dart';
import 'package:maintenance_predictive_mobile/views/shared/dashboard_widgets.dart';

void main() {
  testWidgets('affiche les indicateurs et conserve les accès rapides', (
    WidgetTester tester,
  ) async {
    var actionOpened = false;
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DashboardScaffold(
            title: 'Vue d’ensemble',
            subtitle: 'Pilotez les équipes et la maintenance de l’usine.',
            metrics: const [
              MetricData('Machines', '12', Icons.precision_manufacturing),
              MetricData('Alertes ouvertes', '2', Icons.warning_amber),
              MetricData('Interventions', '5', Icons.build),
            ],
            actions: [
              QuickActionData(
                icon: Icons.groups,
                title: 'Gérer les techniciens',
                subtitle: 'Créer ou modifier un compte',
                onTap: () => actionOpened = true,
              ),
            ],
            statusTitle: 'Données à jour',
            statusSubtitle: 'Dernière synchronisation récente.',
            onRefresh: () async => refreshCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vue d’ensemble'), findsOneWidget);
    expect(find.text('Machines'), findsOneWidget);
    expect(find.text('Alertes ouvertes'), findsOneWidget);
    expect(find.text('Données à jour'), findsOneWidget);
    expect(find.text('Gérer les techniciens'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Gérer les techniciens'));
    expect(actionOpened, isTrue);

    await tester.tap(find.byTooltip('Actualiser les données'));
    await tester.pumpAndSettle();
    expect(refreshCount, 1);
    expect(tester.takeException(), isNull);
  });

  test('applique un bandeau bleu aux AppBars', () {
    final appBarTheme = buildAppTheme().appBarTheme;
    expect(appBarTheme.backgroundColor, AppColors.steel);
    expect(appBarTheme.foregroundColor, Colors.white);
    expect(appBarTheme.shape, isNull);
  });

  testWidgets('distingue le titre de section de la barre bleue', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: AppHeader(
            title: 'Plus',
            subtitle: 'Gestion et analyse · Usine Sfax',
          ),
        ),
      ),
    );

    final header = tester.widget<Container>(
      find
          .ancestor(of: find.text('Plus'), matching: find.byType(Container))
          .first,
    );
    final title = tester.widget<Text>(find.text('Plus'));

    expect(header.decoration, isA<BoxDecoration>());
    expect(
      (header.decoration! as BoxDecoration).color,
      const Color(0xFFE8F0F8),
    );
    expect(title.style?.color, AppColors.navy);
  });

  testWidgets('masque les textes des en-têtes sans supprimer les actions', (
    WidgetTester tester,
  ) async {
    var refreshed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AppHeader(
            trailing: IconButton(
              tooltip: 'Actualiser',
              onPressed: () => refreshed = true,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Plus'), findsNothing);
    expect(find.text('Gestion et analyse · Usine Sfax'), findsNothing);
    expect(find.byTooltip('Actualiser'), findsOneWidget);
    await tester.tap(find.byTooltip('Actualiser'));
    expect(refreshed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('masque le bandeau d’état positif de la page accueil', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DashboardScaffold(
            title: 'Vue d’ensemble',
            subtitle: 'Maintenance de l’usine',
            metrics: const [],
            actions: const [],
            statusTitle: 'Système sous contrôle',
            statusSubtitle: '0 alerte ouverte. Données issues du backend.',
            onRefresh: () async {},
            showStatusBanner: false,
          ),
        ),
      ),
    );

    expect(find.text('Système sous contrôle'), findsNothing);
    expect(
      find.text('0 alerte ouverte. Données issues du backend.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
