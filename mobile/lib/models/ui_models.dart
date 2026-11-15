import 'package:flutter/material.dart';

class MetricData {
  const MetricData(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class QuickActionData {
  const QuickActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}

class FeatureData {
  const FeatureData(this.title, this.description, this.icon);

  final String title;
  final String description;
  final IconData icon;
}
