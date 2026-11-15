import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'offline_store.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serveur injoignable (pas de réseau, PC éteint…), par opposition à une erreur renvoyée par l'API.
class NetworkException extends ApiException {
  const NetworkException(super.message);
}

class ApiClient {
  ApiClient({http.Client? client, OfflineStore? store})
    : _client = client ?? http.Client(),
      store = store ?? MemoryOfflineStore();

  final http.Client _client;

  // ---------- US-28 : mode hors ligne ----------
  final OfflineStore store;

  /// true quand la dernière requête n'a pas pu joindre le serveur.
  final ValueNotifier<bool> offline = ValueNotifier(false);

  /// Nombre d'écritures en attente de synchronisation.
  final ValueNotifier<int> pendingWrites = ValueNotifier(0);

  /// Types des événements temps réel reçus (« machine.etat », « alerte.creee »…) : les pages s'y abonnent
  /// pour se recharger (voir views/shared/live_reload.dart). Alimenté par la page d'accueil.
  final StreamController<String> _changes =
      StreamController<String>.broadcast();
  Stream<String> get changes => _changes.stream;
  void announceChange(String type) {
    if (!_changes.isClosed) _changes.add(type);
  }

  static final _cacheable = RegExp(
    r'^/(interventions(/\d+)?|machines(/\d+)?|alertes|auth/me)$',
  );
  // Écritures acceptées hors ligne : le brouillon du compte rendu (US-06 / US-07)
  static final _queueable = RegExp(r'^/interventions/\d+/compte-rendu$');
  bool _syncing = false;

  String _cacheKey(String path, Map<String, String>? query) =>
      query == null || query.isEmpty
      ? path
      : '$path?${(query.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join('&')}';

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    try {
      final data = await _send(
        method,
        path,
        body: body,
        query: query,
        allowRefresh: allowRefresh,
      );
      if (offline.value) {
        offline.value = false;
        unawaited(syncPending());
      }
      if (method == 'GET' && _cacheable.hasMatch(path)) {
        await store.write(_cacheKey(path, query), data);
      }
      return data;
    } on NetworkException {
      offline.value = true;
      if (method == 'GET' && _cacheable.hasMatch(path)) {
        final cached = await store.read(_cacheKey(path, query));
        if (cached != null) return cached;
      }
      if (method == 'PUT' && _queueable.hasMatch(path) && body != null) {
        await _enqueue(method, path, body);
        return {...body, 'horsLigne': true};
      }
      rethrow;
    }
  }

  Future<void> _enqueue(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    // Un seul brouillon par intervention : le plus récent remplace le précédent
    final items = (await store.pending())
      ..removeWhere((i) => i['method'] == method && i['path'] == path)
      ..add({
        'method': method,
        'path': path,
        'body': body,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    await store.savePending(items);
    pendingWrites.value = items.length;
  }

  /// Rejoue les écritures en attente dans l'ordre. Une écriture refusée par l'API (ex. intervention
  /// clôturée entre-temps) est abandonnée ; une erreur réseau arrête la synchronisation.
  /// Renvoie les messages des écritures abandonnées.
  Future<List<String>> syncPending() async {
    if (_syncing) return const [];
    _syncing = true;
    final rejected = <String>[];
    try {
      final items = await store.pending();
      while (items.isNotEmpty) {
        final item = items.first;
        try {
          await _send(
            item['method'] as String,
            item['path'] as String,
            body: (item['body'] as Map).cast<String, dynamic>(),
          );
        } on NetworkException {
          offline.value = true;
          break;
        } on ApiException catch (e) {
          rejected.add('${item['path']} : ${e.message}');
        }
        items.removeAt(0);
        await store.savePending(items);
      }
      pendingWrites.value = items.length;
    } finally {
      _syncing = false;
    }
    return rejected;
  }

  Future<void> loadPendingCount() async =>
      pendingWrites.value = (await store.pending()).length;
  String? accessToken;
  String? refreshToken;
  Future<void>? _refreshInProgress;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool allowRefresh = true,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}$path',
    ).replace(queryParameters: query);
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    late final http.StreamedResponse response;
    try {
      response = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw NetworkException(
        'Le serveur met trop de temps à répondre (${uri.toString()}). '
        'Vérifiez que le téléphone et le PC sont sur le même réseau, et l’adresse du serveur '
        '(écran de connexion → Serveur).',
      );
    } on http.ClientException {
      throw NetworkException(
        'Impossible de joindre le serveur (${uri.toString()}). '
        'Backend démarré ? Adresse IP du PC à jour (écran de connexion → Serveur) ?',
      );
    }
    final text = await response.stream.bytesToString();
    dynamic data;
    if (text.isNotEmpty) data = jsonDecode(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data is Map ? data['erreur'] : null;
      final errorCode = error is Map ? error['code']?.toString() : null;
      if (allowRefresh &&
          errorCode == 'JETON_EXPIRE' &&
          refreshToken != null &&
          path != '/auth/refresh') {
        await _refreshTokens();
        return _send(
          method,
          path,
          body: body,
          query: query,
          allowRefresh: false,
        );
      }
      final message = data is Map && data['erreur'] is Map
          ? data['erreur']['message']?.toString()
          : null;
      throw ApiException(message ?? 'Erreur serveur (${response.statusCode})');
    }
    if (path == '/auth/refresh' && data is Map<String, dynamic>) {
      accessToken = data['accessToken']?.toString();
      refreshToken = data['refreshToken']?.toString();
    }
    return data;
  }

  Future<void> _refreshTokens() async {
    final pending = _refreshInProgress;
    if (pending != null) return pending;

    final refresh = refreshToken;
    if (refresh == null) {
      throw const ApiException('Session expirée. Veuillez vous reconnecter.');
    }
    final operation = _send(
      'POST',
      '/auth/refresh',
      body: {'refreshToken': refresh},
      allowRefresh: false,
    ).then((_) {});
    _refreshInProgress = operation;
    try {
      await operation;
    } catch (_) {
      accessToken = null;
      refreshToken = null;
      rethrow;
    } finally {
      _refreshInProgress = null;
    }
  }

  /// En-têtes pour charger une image protégée (photos d'intervention, US-25).
  Map<String, String> get authHeaders => {
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };

  /// Envoi d'un fichier (multipart) : photos d'intervention (US-25).
  Future<dynamic> upload(
    String path,
    String field,
    List<int> bytes,
    String filename, {
    Map<String, String> fields = const {},
    bool allowRefresh = true,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}$path'))
          ..headers.addAll(authHeaders)
          ..fields.addAll(fields)
          ..files.add(
            http.MultipartFile.fromBytes(field, bytes, filename: filename),
          );
    late final http.StreamedResponse response;
    try {
      response = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      offline.value = true;
      throw const NetworkException('Envoi trop long : vérifiez le réseau.');
    } on http.ClientException {
      offline.value = true;
      throw const NetworkException('Serveur injoignable : photo non envoyée.');
    }
    final text = await response.stream.bytesToString();
    final data = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode == 401 && allowRefresh && refreshToken != null) {
      await _refreshTokens();
      return upload(
        path,
        field,
        bytes,
        filename,
        fields: fields,
        allowRefresh: false,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data is Map ? data['erreur'] : null;
      throw ApiException(
        error is Map
            ? error['message']?.toString() ?? 'Erreur serveur'
            : 'Erreur serveur (${response.statusCode})',
      );
    }
    return data;
  }

  void dispose() {
    _changes.close();
    _client.close();
  }
}
