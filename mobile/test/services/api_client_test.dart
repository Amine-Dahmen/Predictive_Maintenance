import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:maintenance_predictive_mobile/services/api_client.dart';

void main() {
  test('sends the access token as a Bearer authorization header', () async {
    final transport = _FakeHttpClient([_Response(200, '{}')]);
    final client = ApiClient(client: transport)..accessToken = 'access-token';

    await client.request('GET', '/machines');

    expect(_authorization(transport.requests.single), 'Bearer access-token');
    client.dispose();
  });

  test(
    'refreshes an expired session once and retries the original request',
    () async {
      final transport = _FakeHttpClient([
        _Response(
          401,
          '{"erreur":{"code":"JETON_EXPIRE","message":"Jeton expiré"}}',
        ),
        _Response(
          200,
          '{"accessToken":"new-access","refreshToken":"new-refresh"}',
        ),
        _Response(200, '[]'),
      ]);
      final client = ApiClient(client: transport)
        ..accessToken = 'old-access'
        ..refreshToken = 'old-refresh';

      await client.request('GET', '/machines');

      expect(transport.requests, hasLength(3));
      expect(_authorization(transport.requests[0]), 'Bearer old-access');
      expect(transport.requests[1].url.path, endsWith('/auth/refresh'));
      expect(transport.requests[2].url.path, endsWith('/machines'));
      expect(_authorization(transport.requests[2]), 'Bearer new-access');
      expect(client.refreshToken, 'new-refresh');
      client.dispose();
    },
  );
}

String? _authorization(http.BaseRequest request) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == 'authorization') return entry.value;
  }
  return null;
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responses);

  final List<_Response> _responses;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = _responses.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      request: request,
    );
  }
}
