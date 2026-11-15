// ignore_for_file: use_null_aware_elements

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// En-tête de section qui distingue chaque écran de la barre principale.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    this.title,
    this.subtitle,
    this.caption,
    this.leading,
    this.trailing,
  });

  final String? title;
  final String? subtitle;
  final String? caption;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasText =
        title?.trim().isNotEmpty == true ||
        subtitle?.trim().isNotEmpty == true ||
        caption?.trim().isNotEmpty == true;
    if (!hasText && leading == null && trailing == null) {
      return const SizedBox.shrink();
    }

    final compact = !hasText;
    const sub = TextStyle(color: AppColors.muted, fontSize: 13);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFE8F0F8),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        compact ? 8 : MediaQuery.of(context).padding.top + 16,
        16,
        compact ? 8 : 16,
      ),
      child: Row(
        children: [
          if (leading case final value?) ...[value, const SizedBox(width: 12)],
          if (hasText)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title case final value?)
                    Text(
                      value,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (subtitle case final value?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(value, style: sub),
                    ),
                  if (caption case final value?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(value, style: sub.copyWith(fontSize: 12)),
                    ),
                ],
              ),
            )
          else
            const Spacer(),
          if (trailing case final value?) value,
        ],
      ),
    );
  }
}

/// Bouton carré 48 px pour l'en-tête (notifications, retour...).
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: AppColors.navyLight,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.navyBorder),
        ),
      ),
      icon: Badge(
        isLabelVisible: badgeCount > 0,
        label: Text('$badgeCount'),
        backgroundColor: AppColors.warn,
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

Future<void> showTemporaryPasswordDialog(
  BuildContext context,
  String password,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Compte créé'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Communiquez ce mot de passe provisoire au technicien. '
          'Il ne sera plus affiché.',
        ),
        const SizedBox(height: 12),
        SelectableText(
          password,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Terminé'),
      ),
    ],
  ),
);

/// Carte à bordure fine (pas d'ombre), coins 8 px.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF334155),
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

enum Tone { ok, warn, danger, info, neutral }

/// Étiquette de statut : toujours du TEXTE (jamais la couleur seule).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.tone, {super.key});

  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      Tone.ok => (AppColors.okBg, AppColors.okText),
      Tone.warn => (AppColors.warnBg, AppColors.warnText),
      Tone.danger => (const Color(0xFFFEE4E2), AppColors.danger),
      Tone.info => (AppColors.infoBg, AppColors.infoText),
      Tone.neutral => (AppColors.divider, AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
  });

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

/// Barre de progression / santé (valeur entre 0 et 1).
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: AppColors.divider,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// Ligne titre + sous-titre (+ widget à droite).
class TwoLineTile extends StatelessWidget {
  const TwoLineTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.titleColor,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: titleColor ?? AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (trailing case final value?) ...[const SizedBox(width: 12), value],
      ],
    );
  }
}
