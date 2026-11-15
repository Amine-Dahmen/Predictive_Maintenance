import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maintenance_predictive_mobile/services/api_client.dart';
import 'package:maintenance_predictive_mobile/services/offline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// US-28 : mode hors ligne et synchronisation
void main() {
  late bool networkUp;
  late List<String> received;
  late int status;

  MockClient server() => MockClient((request) async {
    if (!networkUp) throw http.ClientException('Network is unreachable');
    received.add('${request.method} ${request.url.path} ${request.body}');
    if (request.method == 'GET') {
      return http.Response(
        jsonEncode([
          {'id': 1, 'statut': 'EN_COURS'},
        ]),
        200,
      );
    }
    return http.Response(request.body, status);
  });

  setUp(() {
    networkUp = true;
    received = [];
    status = 200;
  });

  test('une lecture déjà faite reste disponible sans réseau', () async {
    final api = ApiClient(client: server());
    final online = await api.request(
      'GET',
      '/interventions',
      query: {'statut': 'EN_COURS'},
    );
    networkUp = false;
    final offline = await api.request(
      'GET',
      '/interventions',
      query: {'statut': 'EN_COURS'},
    );
    expect(offline, online);
    expect(api.offline.value, isTrue);
    // une lecture jamais faite échoue clairement
    await expectLater(
      () => api.request('GET', '/machines/9'),
      throwsA(isA<NetworkException>()),
    );
  });

  test(
    'le brouillon du compte rendu est mis en file puis envoyé au retour du réseau',
    () async {
      final api = ApiClient(client: server());
      networkUp = false;
      final r1 = await api.request(
        'PUT',
        '/interventions/4/compte-rendu',
        body: {'diagnostic': 'v1'},
      );
      final r2 = await api.request(
        'PUT',
        '/interventions/4/compte-rendu',
        body: {'diagnostic': 'v2'},
      );
      expect(r1['horsLigne'], isTrue);
      expect(r2['horsLigne'], isTrue);
      expect(
        api.pendingWrites.value,
        1,
      ); // un seul brouillon par intervention : le plus récent
      // les autres écritures ne sont pas mises en file
      await expectLater(
        () => api.request(
          'PATCH',
          '/interventions/4/cloturer',
          body: {'resultat': 'REMISE_EN_SERVICE'},
        ),
        throwsA(isA<NetworkException>()),
      );

      networkUp = true;
      await api.request(
        'GET',
        '/interventions',
      ); // retour du réseau -> synchronisation automatique
      await Future<void>.delayed(Duration.zero);
      await api.syncPending();
      expect(received.where((r) => r.startsWith('PUT')), [
        'PUT /api/interventions/4/compte-rendu {"diagnostic":"v2"}',
      ]);
      expect(api.pendingWrites.value, 0);
      expect(api.offline.value, isFalse);
    },
  );

  test(
    'une écriture refusée par le serveur est abandonnée et signalée',
    () async {
      final api = ApiClient(client: server());
      networkUp = false;
      await api.request(
        'PUT',
        '/interventions/5/compte-rendu',
        body: {'actions': 'x'},
      );
      networkUp = true;
      status = 409;
      final rejected = await api.syncPending();
      expect(rejected.single, contains('/interventions/5/compte-rendu'));
      expect(api.pendingWrites.value, 0);
    },
  );

  test(
    'le cache et la file survivent au redémarrage de l’application',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = ApiClient(
        client: server(),
        store: PreferencesOfflineStore(),
      );
      await first.request('GET', '/interventions');
      networkUp = false;
      await first.request(
        'PUT',
        '/interventions/6/compte-rendu',
        body: {'diagnostic': 'd'},
      );

      final restarted = ApiClient(
        client: server(),
        store: PreferencesOfflineStore(),
      );
      await restarted.loadPendingCount();
      expect(restarted.pendingWrites.value, 1);
      expect(
        await restarted.request('GET', '/interventions'),
        isA<List<dynamic>>(),
      );
    },
  );
}
