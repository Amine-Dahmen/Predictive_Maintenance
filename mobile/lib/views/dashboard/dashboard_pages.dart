import 'package:flutter/material.dart';
import '../shared/live_reload.dart';

import '../../models/ui_models.dart';
import '../../services/api_client.dart';
import '../../services/dashboard_service.dart';
import '../../viewmodels/dashboard_view_model.dart';
import '../shared/dashboard_widgets.dart';

class ChefDashboardPage extends StatefulWidget {
  const ChefDashboardPage({
    super.key,
    required this.onTechniciansTap,
    required this.apiClient,
    required this.onAlertsTap,
    required this.onMachinesTap,
    required this.onInterventionsTap,
    required this.isDirector,
  });

  final VoidCallback onTechniciansTap;
  final ApiClient apiClient;
  final VoidCallback onAlertsTap;
  final VoidCallback onMachinesTap;
  final VoidCallback onInterventionsTap;
  final bool isDirector;

  @override
  State<ChefDashboardPage> createState() => _ChefDashboardPageState();
}

class _ChefDashboardPageState extends State<ChefDashboardPage>
    with LiveReload<ChefDashboardPage> {
  late final DashboardViewModel viewModel = DashboardViewModel(
    DashboardService(widget.apiClient),
    isChef: true,
  );

  @override
  void initState() {
    super.initState();
    liveReload(widget.apiClient, viewModel.load);
    viewModel.load();
  }

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => _DashboardStateView(
        viewModel: viewModel,
        title: 'Vue d’ensemble',
        subtitle: 'Pilotez les équipes et la maintenance de l’usine.',
        showStatusBanner:
            viewModel.errorMessage != null ||
            viewModel.snapshot?.statusTitle == 'Alertes critiques à traiter',
        icons: const [
          Icons.precision_manufacturing_outlined,
          Icons.check_circle_outline,
          Icons.warning_amber_rounded,
          Icons.error_outline,
          Icons.build_outlined,
          Icons.cloud_off_outlined,
        ],
        actions: [
          QuickActionData(
            icon: widget.isDirector
                ? Icons.admin_panel_settings_outlined
                : Icons.groups_outlined,
            title: widget.isDirector
                ? 'Gérer les responsables'
                : 'Gérer les techniciens',
            subtitle: 'Créer, modifier ou désactiver un compte',
            onTap: widget.onTechniciansTap,
          ),
          QuickActionData(
            icon: Icons.warning_amber_rounded,
            title: 'Traiter les alertes',
            subtitle: 'Consulter les alertes ouvertes depuis le backend',
            onTap: widget.onAlertsTap,
          ),
          QuickActionData(
            icon: Icons.precision_manufacturing_outlined,
            title: 'Consulter les machines',
            subtitle: 'Voir leur état, leurs capteurs et leurs mesures',
            onTap: widget.onMachinesTap,
          ),
          QuickActionData(
            icon: Icons.assignment_outlined,
            title: 'Planifier les interventions',
            subtitle: 'Suivre les interventions enregistrées',
            onTap: widget.onInterventionsTap,
          ),
        ],
      ),
    );
  }
}

class TechnicianDashboardPage extends StatefulWidget {
  const TechnicianDashboardPage({
    super.key,
    required this.apiClient,
    required this.onInterventionsTap,
    required this.onAlertsTap,
    required this.onMachinesTap,
  });

  final ApiClient apiClient;
  final VoidCallback onInterventionsTap;
  final VoidCallback onAlertsTap;
  final VoidCallback onMachinesTap;

  @override
  State<TechnicianDashboardPage> createState() =>
      _TechnicianDashboardPageState();
}

class _TechnicianDashboardPageState extends State<TechnicianDashboardPage>
    with LiveReload<TechnicianDashboardPage> {
  late final DashboardViewModel viewModel = DashboardViewModel(
    DashboardService(widget.apiClient),
    isChef: false,
  );

  @override
  void initState() {
    super.initState();
    liveReload(widget.apiClient, viewModel.load);
    viewModel.load();
  }

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => _DashboardStateView(
        viewModel: viewModel,
        title: 'Mon activité',
        subtitle: 'Retrouvez vos interventions et l’état des machines.',
        showStatusBanner: true,
        icons: const [
          Icons.assignment_late_outlined,
          Icons.timelapse_outlined,
          Icons.task_alt_outlined,
          Icons.warning_amber_rounded,
        ],
        actions: [
          QuickActionData(
            icon: Icons.build_outlined,
            title: 'Mes interventions',
            subtitle: 'Consulter les interventions affectées',
            onTap: widget.onInterventionsTap,
          ),
          QuickActionData(
            icon: Icons.warning_amber_rounded,
            title: 'Alertes machines',
            subtitle: 'Consulter les alertes ouvertes',
            onTap: widget.onAlertsTap,
          ),
          QuickActionData(
            icon: Icons.precision_manufacturing_outlined,
            title: 'État des machines',
            subtitle: 'Consulter les machines et leurs mesures',
            onTap: widget.onMachinesTap,
          ),
        ],
      ),
    );
  }
}

class _DashboardStateView extends StatelessWidget {
  const _DashboardStateView({
    required this.viewModel,
    required this.title,
    required this.subtitle,
    required this.icons,
    required this.actions,
    required this.showStatusBanner,
  });

  final DashboardViewModel viewModel;
  final String title;
  final String subtitle;
  final List<IconData> icons;
  final List<QuickActionData> actions;
  final bool showStatusBanner;

  @override
  Widget build(BuildContext context) {
    final snapshot = viewModel.snapshot;
    final labels = snapshot?.metrics.keys.toList() ?? const <String>[];
    final metrics = [
      for (var index = 0; index < labels.length; index++)
        MetricData(
          labels[index],
          '${snapshot!.metrics[labels[index]]}',
          icons[index],
        ),
    ];

    if (viewModel.isLoading && snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return DashboardScaffold(
      title: title,
      subtitle: subtitle,
      metrics: metrics,
      actions: actions,
      statusTitle: snapshot?.statusTitle ?? 'Données indisponibles',
      statusSubtitle: snapshot?.statusSubtitle ?? viewModel.errorMessage!,
      isError: viewModel.errorMessage != null,
      onRefresh: viewModel.load,
      showStatusBanner: showStatusBanner,
    );
  }
}
