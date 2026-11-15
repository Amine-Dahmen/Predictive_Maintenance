import 'package:flutter/material.dart';

import '../../models/ui_models.dart';
import '../../theme/app_theme.dart';

class DashboardScaffold extends StatelessWidget {
  const DashboardScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.actions,
    required this.statusTitle,
    required this.statusSubtitle,
    required this.onRefresh,
    this.isError = false,
    this.showStatusBanner = true,
  });

  final String title;
  final String subtitle;
  final List<MetricData> metrics;
  final List<QuickActionData> actions;
  final String statusTitle;
  final String statusSubtitle;
  final Future<void> Function() onRefresh;
  final bool isError;
  final bool showStatusBanner;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _DashboardWelcome(
            title: title,
            subtitle: subtitle,
            onRefresh: onRefresh,
          ),
          if (showStatusBanner) ...[
            const SizedBox(height: 16),
            StatusBanner(
              title: statusTitle,
              subtitle: statusSubtitle,
              isError: isError,
            ),
          ],
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionHeading(
              title: 'Indicateurs clés',
              subtitle: 'État actuel de votre activité',
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 520 ? 3 : 2;
                return GridView.builder(
                  itemCount: metrics.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: 118,
                  ),
                  itemBuilder: (_, index) => MetricCard(data: metrics[index]),
                );
              },
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _SectionHeading(
              title: 'Accès rapide',
              subtitle: 'Les tâches les plus utilisées',
            ),
            const SizedBox(height: 10),
            ...actions.map((action) => QuickAction(data: action)),
          ],
        ],
      ),
    );
  }
}

class _DashboardWelcome extends StatelessWidget {
  const _DashboardWelcome({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.steel, AppColors.navy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFE0EAF5),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Actualiser les données',
            onPressed: onRefresh,
            color: Colors.white,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      Text(subtitle, style: const TextStyle(color: AppColors.muted)),
    ],
  );
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.isError = false,
  });

  final String title;
  final String subtitle;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final background = isError ? const Color(0xFFFFEFED) : AppColors.infoBg;
    final foreground = isError ? AppColors.danger : AppColors.infoText;
    return Card(
      elevation: 0,
      color: background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: foreground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: foreground, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.data});

  final MetricData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, color: AppColors.steel, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.data});

  final QuickActionData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(data.icon, color: AppColors.steel),
        ),
        title: Text(
          data.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(data.subtitle),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: AppColors.muted,
        ),
        onTap: data.onTap,
      ),
    );
  }
}
