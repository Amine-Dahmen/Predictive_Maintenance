import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../services/api_client.dart';
import '../../services/realtime_notifications_service.dart';
import '../../viewmodels/role_home_view_model.dart';
import '../alerts/alerts_page.dart';
import '../dashboard/dashboard_pages.dart';
import '../machines/machines_page.dart';
import '../operations/interventions_page.dart';
import 'main_shell.dart';
import '../auth/login_page.dart';
import '../release3/offline_banner.dart';
import '../profile/profile_page.dart';

class RoleHomePage extends StatefulWidget {
  const RoleHomePage({
    super.key,
    required this.role,
    required this.apiClient,
    required this.userName,
  });

  final AppRole role;
  final ApiClient apiClient;
  final String userName;

  @override
  State<RoleHomePage> createState() => _RoleHomePageState();
}

class _RoleHomePageState extends State<RoleHomePage> {
  late final RoleHomeViewModel viewModel;
  late final RealtimeNotificationsService _notifications;
  StreamSubscription<RealtimeEvent>? _notificationSubscription;
  int _notificationCount = 0;
  int _openAlerts = 0;
  final _boards = BoardStatusTracker();
  Timer? _alertsTimer;
  bool _notificationErrorShown = false;

  @override
  void initState() {
    super.initState();
    viewModel = RoleHomeViewModel(widget.role);
    _notifications = RealtimeNotificationsService(widget.apiClient);
    _notificationSubscription = _notifications.events.listen(
      _onRealtimeEvent,
      onError: _onNotificationError,
    );
    _notifications.start();
    widget.apiClient.loadPendingCount();
    widget.apiClient.syncPending();
    _refreshOpenAlerts();
    _alertsTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshOpenAlerts(),
    );
  }

  // Badge de l'onglet Alertes : nombre réel d'alertes ouvertes (30 derniers jours, période par défaut de l'API)
  Future<void> _refreshOpenAlerts() async {
    try {
      final data = await widget.apiClient.request(
        'GET',
        '/alertes',
        query: {'statut': 'OUVERTE', 'limit': '1000'},
      );
      if (mounted && data is List) setState(() => _openAlerts = data.length);
    } catch (_) {
      // badge seulement : l'erreur est déjà visible sur les pages concernées
    }
  }

  @override
  void dispose() {
    _alertsTimer?.cancel();
    unawaited(_notificationSubscription?.cancel());
    unawaited(_notifications.dispose());
    viewModel.dispose();
    widget.apiClient.dispose();
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    widget.apiClient.announceChange(
      event.type,
    ); // les pages ouvertes se rechargent
    // US-35 / US-36 : compte désactivé ou mot de passe réinitialisé -> retour à la connexion
    if (event.type == 'session.revoquee') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        (_) => false,
      );
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Votre session a été fermée par un administrateur.'),
        ),
      );
      return;
    }
    if (event.type.startsWith('alerte.')) _refreshOpenAlerts();
    // Une notification par carte et par changement réel d'état (pas une par capteur ni à chaque mesure)
    if (event.type == 'capteur.etat' && !_boards.shouldNotify(event.data))
      return;
    // US-38 : pas de notification quand le canal APP est coupé ou sous le niveau minimal
    if (event.type == 'alerte.creee' && event.data['notifier'] == false) return;
    final machineCode =
        event.data['machineCode'] ??
        event.data['codeMachine'] ??
        event.data['identifiant'] ??
        'machine';
    final message = switch (event.type) {
      'alerte.creee' =>
        'Nouvelle alerte : ${event.data['typeMesure'] ?? 'anomalie'} '
            '· ${event.data['machineCode'] ?? 'machine'}',
      'intervention.affectee' =>
        widget.role == AppRole.technicien
            ? 'Une intervention vous a été affectée.'
            : 'Une intervention vient d’être affectée.',
      'intervention.retiree' =>
        'Une intervention a été retirée de votre planning.',
      'capteur.etat' =>
        'Capteur ${event.data['enLigne'] == true ? 'en ligne' : 'hors ligne'} '
            '· $machineCode',
      // US-22 : passage au risque de panne élevé
      'prediction.risque' =>
        'Risque de panne élevé · ${event.data['code'] ?? machineCode} '
            '(${((event.data['probabilite'] as num? ?? 0) * 100).round()} %)',
      'machine.etat' =>
        'Machine ${event.data['code'] ?? ''} : ${event.data['etat'] ?? 'état modifié'}.',
      _ => null,
    };
    if (message == null || !mounted) return;
    setState(() {
      _notificationCount++;
      _notificationErrorShown = false;
    });
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _onNotificationError(Object error) {
    if (!mounted || _notificationErrorShown) return;
    _notificationErrorShown = true;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Notifications temps réel indisponibles. Reconnexion…'),
      ),
    );
  }

  void _openNotifications(int destination) {
    setState(() {
      _notificationCount = 0;
      viewModel.selectPage(destination);
    });
  }

  List<Widget> get technicianPages => [
    TechnicianDashboardPage(
      apiClient: widget.apiClient,
      onInterventionsTap: () => viewModel.selectPage(1),
      onMachinesTap: () => viewModel.selectPage(2),
      onAlertsTap: () => _openNotifications(3),
    ),
    InterventionsPage(
      apiClient: widget.apiClient,
      isTechnician: true,
      canManage: false,
    ),
    MachinesPage(
      apiClient: widget.apiClient,
      canManageThresholds: false,
      canOperate: true,
    ),
    AlertsPage(apiClient: widget.apiClient, canCloseAlerts: false),
    ProfilePage(role: AppRole.technicien, apiClient: widget.apiClient),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.role != AppRole.technicien) {
      return MainShell(
        apiClient: widget.apiClient,
        role: widget.role,
        notificationCount: _notificationCount,
        openAlerts: _openAlerts,
        onNotificationsOpened: () => setState(() => _notificationCount = 0),
      );
    }

    final destinations = [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Accueil',
      ),
      NavigationDestination(
        icon: Icon(Icons.build_outlined),
        selectedIcon: Icon(Icons.build),
        label: 'Interventions',
      ),
      NavigationDestination(
        icon: Icon(Icons.precision_manufacturing_outlined),
        selectedIcon: Icon(Icons.precision_manufacturing),
        label: 'Machines',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: _openAlerts > 0,
          label: Text('$_openAlerts'),
          child: const Icon(Icons.warning_amber_outlined),
        ),
        selectedIcon: const Icon(Icons.warning_amber),
        label: 'Alertes',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profil',
      ),
    ];

    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              onPressed: () => _openNotifications(3),
              tooltip: 'Notifications',
              icon: Badge(
                isLabelVisible: _notificationCount > 0,
                label: Text('$_notificationCount'),
                child: const Icon(
                  Icons.notifications_none,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            OfflineBanner(apiClient: widget.apiClient),
            Expanded(
              child: IndexedStack(
                index: viewModel.selectedIndex,
                children: technicianPages,
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: viewModel.selectedIndex,
          onDestinationSelected: (index) {
            if (index == 3) {
              _openNotifications(index);
            } else {
              viewModel.selectPage(index);
            }
          },
          destinations: destinations,
        ),
      ),
    );
  }
}
