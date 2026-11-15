import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../models/app_role.dart';
import '../alerts/alerts_page.dart';
import '../dashboard/dashboard_pages.dart';
import '../machines/machines_page.dart';
import '../operations/interventions_page.dart';
import '../profile/profile_page.dart';
import 'more_screen.dart';
import '../release3/offline_banner.dart';
import '../users/responsables_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.apiClient,
    required this.role,
    required this.notificationCount,
    this.openAlerts = 0,
    required this.onNotificationsOpened,
  });

  final ApiClient apiClient;
  final AppRole role;
  final int notificationCount;
  final int openAlerts;
  final VoidCallback onNotificationsOpened;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void _go(int index) {
    if (index == 1) widget.onNotificationsOpened();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChefDashboardPage(
        apiClient: widget.apiClient,
        onTechniciansTap: () => _go(4),
        onAlertsTap: () => _go(1),
        onMachinesTap: () => _go(2),
        onInterventionsTap: () => _go(3),
        isDirector: widget.role == AppRole.directeur,
      ),
      AlertsPage(
        apiClient: widget.apiClient,
        canCloseAlerts: widget.role == AppRole.chefProduction,
        canAcknowledge: widget.role == AppRole.chefProduction,
      ),
      MachinesPage(
        apiClient: widget.apiClient,
        canManageThresholds: widget.role == AppRole.chefProduction,
        canOperate: widget.role == AppRole.chefProduction,
      ),
      InterventionsPage(
        apiClient: widget.apiClient,
        isTechnician: false,
        canManage: widget.role == AppRole.chefProduction,
      ),
      widget.role == AppRole.directeur
          ? ResponsablesPage(apiClient: widget.apiClient)
          : MoreScreen(
              apiClient: widget.apiClient,
              onNotificationsTap: () => _go(1),
              onMachinesTap: () => _go(2),
            ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance prédictive'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              _go(1);
            },
            icon: Badge(
              isLabelVisible: widget.notificationCount > 0,
              label: Text('${widget.notificationCount}'),
              child: const Icon(Icons.notifications_none),
            ),
          ),
          IconButton(
            tooltip: 'Profil',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ProfilePage(role: widget.role, apiClient: widget.apiClient),
              ),
            ),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(apiClient: widget.apiClient),
          Expanded(
            child: IndexedStack(index: _index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.openAlerts > 0,
              label: Text('${widget.openAlerts}'),
              child: const Icon(Icons.warning_amber),
            ),
            selectedIcon: Badge(
              isLabelVisible: widget.openAlerts > 0,
              label: Text('${widget.openAlerts}'),
              child: const Icon(Icons.warning),
            ),
            label: 'Alertes',
          ),
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: 'Machines',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Interventions',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu),
            selectedIcon: Icon(Icons.menu_open),
            label: 'Plus',
          ),
        ],
      ),
    );
  }
}
