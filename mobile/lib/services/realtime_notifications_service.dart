import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_client.dart';

class RealtimeEvent {
  const RealtimeEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

class RealtimeNotificationsService {
  RealtimeNotificationsService(this.apiClient) : _client = http.Client();

  final ApiClient apiClient;
  final http.Client _client;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  StreamSubscription<String>? _connection;
  bool _isRunning = false;
  Future<void>? _runTask;

  Stream<RealtimeEvent> get events => _events.stream;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _runTask = _run();
  }

  Future<void> _run() async {
    while (_isRunning) {
      final token = apiClient.accessToken;
      if (token == null) return;
      try {
        await _connect(token);
      } catch (error, stackTrace) {
        if (!_isRunning) return;
        _events.addError(error, stackTrace);
        if (error is _UnauthorizedStreamException) {
          final refreshToken = apiClient.refreshToken;
          if (refreshToken == null) return;
          try {
            await apiClient.request(
              'POST',
              '/auth/refresh',
              body: {'refreshToken': refreshToken},
              allowRefresh: false,
            );
          } catch (refreshError, refreshStack) {
            if (_isRunning) _events.addError(refreshError, refreshStack);
            return;
          }
        } else {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
      if (_isRunning) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _connect(String token) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/stream',
    ).replace(queryParameters: {'token': token});
    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'text/event-stream';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) {
      await response.stream.drain<void>();
      throw const _UnauthorizedStreamException();
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw ApiException(
        'Le flux de notifications a répondu HTTP ${response.statusCode}.',
      );
    }

    var eventName = 'message';
    final data = StringBuffer();
    final completed = Completer<void>();
    final subscription = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.isEmpty) {
              if (data.isNotEmpty) {
                final decoded = jsonDecode(data.toString().trimRight());
                if (decoded is Map<String, dynamic>) {
                  _events.add(RealtimeEvent(eventName, decoded));
                } else {
                  if (!completed.isCompleted) {
                    completed.completeError(
                      const FormatException(
                        'Le flux de notifications contient un événement invalide.',
                      ),
                    );
                  }
                  return;
                }
              }
              eventName = 'message';
              data.clear();
              return;
            }
            if (line.startsWith(':')) return;
            final separator = line.indexOf(':');
            final field = separator < 0 ? line : line.substring(0, separator);
            final value = separator < 0 ? '' : line.substring(separator + 1);
            final normalized = value.startsWith(' ')
                ? value.substring(1)
                : value;
            if (field == 'event') eventName = normalized;
            if (field == 'data') data.writeln(normalized);
          },
          onError: completed.completeError,
          onDone: () {
            if (!completed.isCompleted) completed.complete();
          },
          cancelOnError: true,
        );
    _connection = subscription;
    try {
      await completed.future;
    } finally {
      if (identical(_connection, subscription)) _connection = null;
      await subscription.cancel();
    }
  }

  Future<void> dispose() async {
    _isRunning = false;
    await _connection?.cancel();
    await _runTask;
    _client.close();
    await _events.close();
  }
}

class _UnauthorizedStreamException implements Exception {
  const _UnauthorizedStreamException();
}

/// Notifications de connexion des cartes : une par carte et par changement réel d'état. Le backend
/// signale le passage hors ligne puis le retour en ligne ; les répétitions sont ignorées, et un premier
/// « en ligne » (état déjà connu au démarrage) ne notifie pas.
class BoardStatusTracker {
  final Map<String, bool> _online = {};

  bool shouldNotify(Map<String, dynamic> data) {
    final key =
        '${data['machineId'] ?? data['codeMachine'] ?? data['identifiant']}';
    final online = data['enLigne'] == true;
    final previous = _online[key];
    _online[key] = online;
    return previous != online && !(previous == null && online);
  }
}
