import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maintenance_predictive_mobile/config/api_config.dart';
import 'package:maintenance_predictive_mobile/views/auth/server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Adresse du serveur réglable dans l'application (l'IP du PC change avec le réseau / le point d'accès)
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('une IP seule devient l’URL complète de l’API', () {
    expect(
      ApiConfig.normalize('192.168.45.116'),
      'http://192.168.45.116:3000/api',
    );
    expect(
      ApiConfig.normalize(' 192.168.45.116:3100 '),
      'http://192.168.45.116:3100/api',
    );
    expect(
      ApiConfig.normalize('http://10.0.0.5:3000/api/'),
      'http://10.0.0.5:3000/api',
    );
    expect(
      ApiConfig.normalize('https://pc.local'),
      'https://pc.local:3000/api',
    );
    expect(ApiConfig.normalize(''), isNull);
    expect(ApiConfig.normalize('ftp://x'), isNull);
    expect(ApiConfig.normalize('pas une adresse'), isNull);
  });

  test(
    'l’adresse enregistrée est relue au démarrage, « par défaut » l’efface',
    () async {
      await ApiConfig.save('http://192.168.1.50:3000/api');
      await ApiConfig.reset();
      expect(ApiConfig.baseUrl, ApiConfig.defaultBaseUrl);
      SharedPreferences.setMockInitialValues({
        'api-base-url': 'http://192.168.1.50:3000/api',
      });
      await ApiConfig.load();
      expect(ApiConfig.baseUrl, 'http://192.168.1.50:3000/api');
      expect(ApiConfig.displayAddress, '192.168.1.50:3000');
      await ApiConfig.reset();
    },
  );

  test(
    'test de connexion : API PrédiMaint, autre serveur, injoignable',
    () async {
      final ok = MockClient(
        (r) async => http.Response('{"statut":"ok","mqtt":"connecte"}', 200),
      );
      final other = MockClient((r) async => http.Response('<html>', 404));
      final down = MockClient(
        (r) async => throw http.ClientException('No route to host'),
      );
      expect(await ApiConfig.check('http://pc:3000/api', client: ok), isNull);
      expect(
        await ApiConfig.check('http://pc:3000/api', client: other),
        contains('HTTP 404'),
      );
      expect(
        await ApiConfig.check('http://pc:3000/api', client: down),
        contains('injoignable'),
      );
    },
  );

  testWidgets('la saisie d’une nouvelle IP est enregistrée et affichée', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ServerAddressTile())),
    );
    expect(
      find.textContaining('Serveur : ${ApiConfig.displayAddress}'),
      findsOneWidget,
    );
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '192.168.43.20');
    await tester.pump();
    expect(find.text('→ http://192.168.43.20:3000/api'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Serveur : 192.168.43.20:3000'), findsOneWidget);
    expect(ApiConfig.baseUrl, 'http://192.168.43.20:3000/api');
    expect(
      (await SharedPreferences.getInstance()).getString('api-base-url'),
      'http://192.168.43.20:3000/api',
    );
    await ApiConfig.reset();
  });
}
