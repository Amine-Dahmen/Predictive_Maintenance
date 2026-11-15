import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Adresse de l'API. Elle se règle DANS l'application (écran de connexion → « Serveur ») et reste
/// enregistrée sur le téléphone : quand l'adresse IP du PC change, il suffit de la corriger là,
/// sans recompiler.
///
/// Valeur par défaut : --dart-define=API_BASE_URL=... à la compilation, sinon l'adresse du PC sur le
/// point d'accès du téléphone utilisé pour le projet (réseau « BHK », 13/11/2026).
class ApiConfig {
  const ApiConfig._();

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.45.116:3000/api',
  );
  static const defaultPort = 3000;
  static const _prefsKey = 'api-base-url';

  static String _baseUrl = defaultBaseUrl;

  static String get baseUrl => _baseUrl;

  /// Adresse courte affichée à l'utilisateur, ex. « 192.168.45.116:3000 ».
  static String get displayAddress {
    final uri = Uri.parse(_baseUrl);
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// Lit l'adresse enregistrée (appelé au démarrage de l'application).
  static Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        _prefsKey,
      );
      final normalized = saved == null ? null : normalize(saved);
      _baseUrl = normalized ?? defaultBaseUrl;
    } catch (_) {
      _baseUrl = defaultBaseUrl; // stockage indisponible : valeur par défaut
    }
  }

  static Future<void> save(String url) async {
    _baseUrl = url;
    await (await SharedPreferences.getInstance()).setString(_prefsKey, url);
  }

  static Future<void> reset() async {
    _baseUrl = defaultBaseUrl;
    await (await SharedPreferences.getInstance()).remove(_prefsKey);
  }

  /// Accepte « 192.168.45.116 », « 192.168.45.116:3000 », « http://pc.local:3000 » ou une URL complète
  /// et renvoie « http://hôte:port/api ». null si la saisie n'est pas une adresse.
  static String? normalize(String input) {
    var text = input.trim();
    if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    final port = uri.hasPort ? uri.port : defaultPort;
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (!path.endsWith('/api')) path = '$path/api';
    return '${uri.scheme}://${uri.host}:$port$path';
  }

  /// Vérifie qu'un backend PrédiMaint répond (GET /api/health). Renvoie null si tout va bien,
  /// sinon un message d'aide.
  static Future<String?> check(String url, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200 && r.body.contains('"statut"')) return null;
      return 'Le serveur répond (HTTP ${r.statusCode}) mais ce n’est pas l’API PrédiMaint.';
    } on TimeoutException {
      return 'Pas de réponse de $url : vérifiez l’adresse IP du PC et que le téléphone '
          'est sur le même réseau (ou partage sa connexion avec le PC).';
    } catch (_) {
      return 'Serveur injoignable ($url) : backend démarré ? bonne adresse IP ?';
    } finally {
      if (client == null) c.close();
    }
  }
}
