import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// The eight dashboard quick actions. Each entry is purely declarative —
/// the dashboard renders the grid by mapping over [QuickAction.values].
///
/// [routePath] is null when the action is "coming soon" — those tiles show
/// a snackbar instead of navigating to a placeholder screen.
enum QuickAction {
  scanPrescription(
    label: 'Scan\nPrescription',
    icon: Icons.center_focus_strong_rounded,
    tint: AppColors.tintBlue,
    routePath: '/scan',
  ),
  uploadReport(
    label: 'Upload\nReport',
    icon: Icons.upload_file_rounded,
    tint: AppColors.tintCyan,
    routePath: '/reports',
  ),
  aiAssistant(
    label: 'AI\nAssistant',
    icon: Icons.auto_awesome_rounded,
    tint: AppColors.tintViolet,
    routePath: '/assistant',
  ),
  drugInteraction(
    label: 'Drug\nInteraction',
    icon: Icons.compare_arrows_rounded,
    tint: AppColors.tintAmber,
    routePath: '/interactions',
  ),
  medicineReminder(
    label: 'Medicine\nReminder',
    icon: Icons.alarm_rounded,
    tint: AppColors.tintGreen,
    routePath: '/reminders',
  ),
  healthRisk(
    label: 'Health Risk\nInsights',
    icon: Icons.insights_rounded,
    tint: AppColors.tintBlue,
    routePath: '/health-insights',
  ),
  genericSwap(
    label: 'Generic\nSwap',
    icon: Icons.savings_rounded,
    tint: AppColors.tintGreen,
    routePath: '/savings',
  ),
  nearbyPharmacies(
    label: 'Nearby\nPharmacies',
    icon: Icons.local_pharmacy_rounded,
    tint: AppColors.tintCyan,
    routePath: '/pharmacies',
  ),
  emergencyContacts(
    label: 'Emergency\nContacts',
    icon: Icons.contact_emergency_rounded,
    tint: AppColors.tintRed,
    routePath: '/sos',
  ),
  symptomCheck(
    label: 'Symptom\nCheck',
    icon: Icons.fact_check_rounded,
    tint: AppColors.tintViolet,
    routePath: '/symptom-check',
  );

  const QuickAction({
    required this.label,
    required this.icon,
    required this.tint,
    required this.routePath,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final String? routePath;
}
