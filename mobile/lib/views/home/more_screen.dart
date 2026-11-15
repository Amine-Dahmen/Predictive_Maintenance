import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../models/technician.dart';
import '../../theme/app_theme.dart';
import '../../services/api_client.dart';
import '../../services/technicians_service.dart';
import '../../viewmodels/technicians_view_model.dart';
import '../common.dart';
import '../profile/profile_page.dart';
import '../technicians/technicians_page.dart';

/// Écran de référence « Plus » pour la gestion et l'analyse.
///
/// Cette version sert de maquette visuelle. Les compteurs et les actions
/// seront reliés aux ViewModels et aux endpoints backend après validation.
class MoreScreen extends StatefulWidget {
  const MoreScreen({
    super.key,
    required this.apiClient,
    required this.onNotificationsTap,
    required this.onMachinesTap,
  });

  final ApiClient apiClient;
  final VoidCallback onNotificationsTap;
  final VoidCallback onMachinesTap;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  late final TechniciansViewModel _technicians;

  @override
  void initState() {
    super.initState();
    _technicians = TechniciansViewModel(TechniciansService(widget.apiClient))
      ..load();
  }

  @override
  void dispose() {
    _technicians.dispose();
    super.dispose();
  }

  Future<void> _createTechnician() async {
    final technician = await showDialog<Technician>(
      context: context,
      builder: (_) => const TechnicianFormDialog(),
    );
    if (!mounted || technician == null) return;
    final temporaryPassword = await _technicians.saveTechnician(technician);
    if (mounted && temporaryPassword != null) {
      await showTemporaryPasswordDialog(context, temporaryPassword);
    }
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(
          role: AppRole.chefProduction,
          apiClient: widget.apiClient,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Future<void> openTechnicians() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TechniciansPage(service: TechniciansService(widget.apiClient)),
        ),
      );
      if (mounted) {
        await _technicians.load();
      }
    }

    return AnimatedBuilder(
      animation: _technicians,
      builder: (context, _) => ListView(
        padding: EdgeInsets.zero,
        children: [
          const AppHeader(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Techniciens'),
                const SizedBox(height: 8),
                AppCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _Stat(
                              '${_technicians.technicians.length}',
                              'Total',
                              AppColors.ink,
                            ),
                          ),
                          Expanded(
                            child: _Stat(
                              '${_technicians.technicians.where((item) => item.active).length}',
                              'Actifs',
                              AppColors.okText,
                            ),
                          ),
                          Expanded(
                            child: _Stat(
                              '${_technicians.technicians.where((item) => !item.active).length}',
                              'Désactivés',
                              AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                      if (_technicians.isLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
                        ),
                      if (_technicians.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _technicians.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: openTechnicians,
                              child: const Text('Gérer les techniciens'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _createTechnician,
                            child: const Text('+ Créer'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Group(
                  title: 'Équipements',
                  items: [
                    _Item(
                      'Machines',
                      'Ajouter, modifier, suivre l’état',
                      widget.onMachinesTap,
                    ),
                    _Item(
                      'Capteurs',
                      'Configurer et associer aux machines',
                      widget.onMachinesTap,
                    ),
                    _Item(
                      'Seuils vibration et courant',
                      'Définir les limites d’alerte',
                      widget.onMachinesTap,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Group(
                  title: 'Analyse',
                  items: [
                    _Item(
                      'Mesures et historiques',
                      'Courbes par capteur et par période',
                      widget.onMachinesTap,
                    ),
                    _Item(
                      'Indicateurs',
                      'MTBF · MTTR · disponibilité · TRS',
                      () {},
                    ),
                    _Item(
                      'Ordres de fabrication',
                      'Suivi de la production',
                      () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Group(
                  title: 'Compte',
                  items: [
                    _Item(
                      'Profil',
                      'Informations et préférences',
                      _openProfile,
                    ),
                    _Item(
                      'Notifications temps réel',
                      'Alertes, machines, interventions',
                      widget.onNotificationsTap,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _Item {
  const _Item(this.title, this.subtitle, this.onTap);

  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items});

  final String title;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        const SizedBox(height: 8),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                InkWell(
                  onTap: items[index].onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: TwoLineTile(
                      title: items[index].title,
                      subtitle: items[index].subtitle,
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
