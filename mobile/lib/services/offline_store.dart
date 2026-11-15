import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// US-28 : stockage du mode hors ligne.
///  - cache : dernière réponse des lectures utiles sur le terrain (interventions, machines, alertes)
///  - file d'attente : écritures faites sans réseau, rejouées dans l'ordre au retour du réseau
abstract class OfflineStore {
  Future<dynamic> read(String key);
  Future<void> write(String key, dynamic value);
  Future<List<Map<String, dynamic>>> pending();
  Future<void> savePending(List<Map<String, dynamic>> items);
}

/// Mémoire seule (tests, ou si le stockage du téléphone est indisponible).
class MemoryOfflineStore implements OfflineStore {
  final Map<String, String> _cache = {};
  List<Map<String, dynamic>> _pending = [];

  @override
  Future<dynamic> read(String key) async =>
      _cache[key] == null ? null : jsonDecode(_cache[key]!);

  @override
  Future<void> write(String key, dynamic value) async =>
      _cache[key] = jsonEncode(value);

  @override
  Future<List<Map<String, dynamic>>> pending() async => [..._pending];

  @override
  Future<void> savePending(List<Map<String, dynamic>> items) async =>
      _pending = [...items];
}

/// Stockage persistant (survit à la fermeture de l'application).
class PreferencesOfflineStore implements OfflineStore {
  static const _prefix = 'cache:';
  static const _pendingKey = 'pending-writes';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<dynamic> read(String key) async {
    final raw = (await _prefs).getString('$_prefix$key');
    return raw == null ? null : jsonDecode(raw);
  }

  @override
  Future<void> write(String key, dynamic value) async =>
      (await _prefs).setString('$_prefix$key', jsonEncode(value));

  @override
  Future<List<Map<String, dynamic>>> pending() async {
    final raw = (await _prefs).getString(_pendingKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().toList();
  }

  @override
  Future<void> savePending(List<Map<String, dynamic>> items) async =>
      (await _prefs).setString(_pendingKey, jsonEncode(items));
}
