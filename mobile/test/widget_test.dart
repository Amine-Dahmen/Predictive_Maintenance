import 'package:flutter_test/flutter_test.dart';

import 'package:maintenance_predictive_mobile/main.dart';

void main() {
  testWidgets('affiche la connexion avec les deux rôles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaintenancePredictiveApp());

    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('prédictive'), findsOneWidget);
    expect(find.text('Accédez à votre espace'), findsOneWidget);
    expect(find.text('Adresse e-mail'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
  });
}
