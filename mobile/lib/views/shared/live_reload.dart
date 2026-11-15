import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/api_client.dart';

/// Rechargement d'une page quand le serveur annonce un changement sur le flux temps réel (état d'une
/// machine, alerte, intervention, capteur, prédiction) ou quand le flux se reconnecte après une coupure.
/// Sans cela, une page restée ouverte (les onglets sont conservés) montrait un état périmé, différent du
/// site web qui, lui, suit ces événements.
mixin LiveReload<T extends StatefulWidget> on State<T> {
  static const defaultTypes = {
    'machine.',
    'alerte.',
    'intervention.',
    'capteur.',
    'prediction.',
    'firmware.',
    'connecte',
  };

  StreamSubscription<String>? _liveSubscription;
  Timer? _liveDebounce;

  /// [reload] est appelé une fois par fenêtre de [debounce] après un événement : les événements d'une
  /// rafale sont regroupés, et un flux continu (une mesure toutes les 5 s) recharge à intervalle régulier
  /// au lieu de repousser indéfiniment le rechargement.
  void liveReload(
    ApiClient api,
    FutureOr<void> Function() reload, {
    Set<String> types = defaultTypes,
    Duration debounce = const Duration(milliseconds: 800),
  }) {
    _liveSubscription?.cancel();
    _liveSubscription = api.changes
        .where((type) => types.any(type.startsWith))
        .listen((_) {
          _liveDebounce ??= Timer(debounce, () {
            _liveDebounce = null;
            if (mounted) reload();
          });
        });
  }

  @override
  void dispose() {
    _liveDebounce?.cancel();
    _liveSubscription?.cancel();
    super.dispose();
  }
}
