import 'package:flutter/material.dart';

import '../../models/technician.dart';
import '../../services/technicians_service.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/technicians_view_model.dart';
import '../common.dart';

enum TechFilter { all, active, inactive }

class TechniciansPage extends StatefulWidget {
  const TechniciansPage({super.key, required this.service});

  final TechniciansService service;

  @override
  State<TechniciansPage> createState() => _TechniciansPageState();
}

class _TechniciansPageState extends State<TechniciansPage> {
  static const _pageSize = 20;
  TechniciansViewModel? _viewModel;
  final _searchController = TextEditingController();
  TechFilter _filter = TechFilter.all;
  String _query = '';
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    _model.load();
  }

  TechniciansViewModel get _model =>
      _viewModel ??= TechniciansViewModel(widget.service);

  @override
  void dispose() {
    _searchController.dispose();
    _viewModel?.dispose();
    super.dispose();
  }

  List<Technician> get _filtered {
    final query = _query.toLowerCase();
    return _model.technicians.where((technician) {
      final matchesFilter = switch (_filter) {
        TechFilter.all => true,
        TechFilter.active => technician.active,
        TechFilter.inactive => !technician.active,
      };
      final matchesQuery =
          query.isEmpty ||
          technician.name.toLowerCase().contains(query) ||
          technician.specialty.toLowerCase().contains(query) ||
          technician.email.toLowerCase().contains(query);
      return matchesFilter && matchesQuery;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  int _count(TechFilter filter) {
    return _model.technicians.where((technician) {
      return switch (filter) {
        TechFilter.all => true,
        TechFilter.active => technician.active,
        TechFilter.inactive => !technician.active,
      };
    }).length;
  }

  String _label(TechFilter filter) => switch (filter) {
    TechFilter.all => 'Tous',
    TechFilter.active => 'Actifs',
    TechFilter.inactive => 'Désactivés',
  };

  Future<void> _showTechnicianForm([Technician? technician]) async {
    final result = await showDialog<Technician>(
      context: context,
      builder: (_) => TechnicianFormDialog(technician: technician),
    );
    if (!mounted || result == null) return;
    final temporaryPassword = await _model.saveTechnician(
      result,
      existing: technician,
    );
    if (mounted && temporaryPassword != null) {
      await showTemporaryPasswordDialog(context, temporaryPassword);
    }
  }

  Future<void> _resetPassword(Technician technician) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réinitialiser le mot de passe ?'),
        content: Text(
          '${technician.name} recevra un mot de passe provisoire à changer à la '
          'prochaine connexion. Ses sessions ouvertes seront fermées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final temporaryPassword = await _model.resetPassword(technician);
    if (mounted && temporaryPassword != null) {
      await showTemporaryPasswordDialog(context, temporaryPassword);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _model,
      builder: (context, _) {
        final filtered = _filtered;
        final shown = filtered.take(_visible).toList();
        final hasMore = filtered.length > shown.length;
        final remaining = filtered.length - shown.length;

        return Scaffold(
          body: Column(
            children: [
              AppHeader(
                title: 'Techniciens',
                subtitle:
                    '${_model.technicians.length} comptes · '
                    '${_count(TechFilter.active)} actifs',
                leading: HeaderIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Retour',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                trailing: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.navy,
                    minimumSize: const Size(72, 44),
                  ),
                  onPressed: _showTechnicianForm,
                  child: const Text('+ Créer'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() {
                    _query = value;
                    _visible = _pageSize;
                  }),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un nom, une spécialité',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.muted,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.steel,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              if (_model.isLoading)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                ),
              if (_model.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _model.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: TechFilter.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final filter = TechFilter.values[index];
                    final selected = filter == _filter;
                    return ChoiceChip(
                      label: Text('${_label(filter)} · ${_count(filter)}'),
                      selected: selected,
                      showCheckmark: false,
                      selectedColor: AppColors.steel,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: selected ? AppColors.steel : AppColors.border,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF334155),
                      ),
                      onSelected: (_) => setState(() {
                        _filter = filter;
                        _visible = _pageSize;
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    filtered.isEmpty
                        ? 'Aucun résultat'
                        : '1–${shown.length} sur ${filtered.length} · tri : nom A→Z',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: shown.length + (hasMore ? 1 : 0),
                  itemBuilder: (_, index) {
                    if (index == shown.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _visible += _pageSize),
                          child: Text(
                            'Charger ${remaining < _pageSize ? remaining : _pageSize} de plus',
                          ),
                        ),
                      );
                    }
                    final technician = shown[index];
                    return _TechnicianTile(
                      technician: technician,
                      isFirst: index == 0,
                      isLast: index == shown.length - 1 && !hasMore,
                      onEdit: () => _showTechnicianForm(technician),
                      onResetPassword: () => _resetPassword(technician),
                      onToggle: (active) async {
                        if (technician.id == null) return;
                        await _model.toggleStatus(
                          _model.technicians.indexOf(technician),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TechnicianTile extends StatelessWidget {
  const _TechnicianTile({
    required this.technician,
    required this.onEdit,
    this.onResetPassword,
    required this.onToggle,
    required this.isFirst,
    required this.isLast,
  });

  final Technician technician;
  final VoidCallback onEdit;
  final VoidCallback? onResetPassword;
  final ValueChanged<bool> onToggle;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final name = technician.name.trim();
    final initials = name
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
        .join();
    final subtitle = technician.active
        ? '${technician.specialty} · disponible'
        : '${technician.specialty} · compte désactivé';

    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: isFirst || isLast
              ? Border.all(color: AppColors.border)
              : const Border(
                  left: BorderSide(color: AppColors.border),
                  right: BorderSide(color: AppColors.border),
                  top: BorderSide(color: AppColors.divider),
                ),
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(8) : Radius.zero,
            bottom: isLast ? const Radius.circular(8) : Radius.zero,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.infoBg,
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.infoText,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TwoLineTile(
                title: name,
                subtitle: subtitle,
                titleColor: technician.active ? AppColors.ink : AppColors.muted,
              ),
            ),
            if (onResetPassword != null && technician.active)
              IconButton(
                tooltip: 'Réinitialiser le mot de passe',
                onPressed: onResetPassword,
                icon: const Icon(Icons.lock_reset),
              ),
            Switch(
              value: technician.active,
              onChanged: onToggle,
              activeTrackColor: AppColors.ok,
              activeThumbColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class TechnicianFormDialog extends StatefulWidget {
  const TechnicianFormDialog({super.key, this.technician});

  final Technician? technician;

  @override
  State<TechnicianFormDialog> createState() => _TechnicianFormDialogState();
}

class _TechnicianFormDialogState extends State<TechnicianFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nom;
  late final TextEditingController _prenom;
  late final TextEditingController _email;
  late final TextEditingController _specialty;

  @override
  void initState() {
    super.initState();
    _nom = TextEditingController(text: widget.technician?.nom);
    _prenom = TextEditingController(text: widget.technician?.prenom);
    _email = TextEditingController(text: widget.technician?.email);
    _specialty = TextEditingController(text: widget.technician?.specialty);
  }

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _specialty.dispose();
    super.dispose();
  }

  String? _required(String? value, String label) {
    return value == null || value.trim().isEmpty
        ? '$label est obligatoire'
        : null;
  }

  String? _emailValidator(String? value) {
    final required = _required(value, 'L’e-mail');
    if (required != null) return required;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value!.trim())
        ? null
        : 'E-mail invalide';
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      Technician(
        widget.technician?.id,
        _nom.text.trim(),
        _prenom.text.trim(),
        _email.text.trim().toLowerCase(),
        _specialty.text.trim(),
        widget.technician?.active ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.technician == null
            ? 'Nouveau technicien'
            : 'Modifier le technicien',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nom,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (value) => _required(value, 'Le nom'),
              ),
              TextFormField(
                controller: _prenom,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (value) => _required(value, 'Le prénom'),
              ),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: _emailValidator,
              ),
              TextFormField(
                controller: _specialty,
                decoration: const InputDecoration(labelText: 'Spécialité'),
                validator: (value) => _required(value, 'La spécialité'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
