// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navAssistant => 'Assistant';

  @override
  String get navScan => 'Scan';

  @override
  String get navReports => 'Reports';

  @override
  String get navProfile => 'Profile';

  @override
  String get dashboardTitle => 'Health dashboard';

  @override
  String get dashboardSubtitle => 'Synced with your medical records';

  @override
  String get statMedicines => 'Medicines';

  @override
  String get statAlerts => 'Alerts';

  @override
  String get statAllClear => 'All clear';

  @override
  String get statReviewNow => 'Review now';

  @override
  String statScansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scans',
      one: '1 scan',
      zero: '0 scans',
    );
    return '$_temp0';
  }

  @override
  String get quickActionsTitle => 'Quick actions';

  @override
  String get quickActionMedicineReminder => 'Medicine\nReminder';

  @override
  String get quickActionNearbyPharmacies => 'Nearby\nPharmacies';

  @override
  String get quickActionHealthRisk => 'Health Risk\nInsights';

  @override
  String get quickActionEmergencyContacts => 'Emergency\nContacts';

  @override
  String get quickActionGenericSwap => 'Generic\nSwap';

  @override
  String get nextDoseLabel => 'NEXT DOSE';

  @override
  String get nextDoseNone => 'No pending reminders';

  @override
  String get nextDoseClear => 'Everything is clear';

  @override
  String adherenceStreak(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days-day streak',
      one: '1-day streak',
      zero: 'No active streak',
    );
    return '$_temp0';
  }

  @override
  String get adherenceLabel => 'Adherence';

  @override
  String get adherenceNoData => 'No adherence data yet';

  @override
  String get adherenceNoDataHint =>
      'Mark doses taken or missed to start a streak.';

  @override
  String get recentActivityTitle => 'Recent activity';

  @override
  String get viewAll => 'View all';

  @override
  String get noActivityTitle => 'No activity yet';

  @override
  String get noActivityHint =>
      'Scan a prescription or upload a report to get started.';

  @override
  String get noNewNotifications => 'No new notifications';

  @override
  String comingSoon(String label) {
    return '$label — coming soon';
  }

  @override
  String get doseSlotMorning => 'Morning dose';

  @override
  String get doseSlotAfternoon => 'Afternoon dose';

  @override
  String get doseSlotNight => 'Night dose';

  @override
  String get activityPrescriptionScan => 'Prescription scan';

  @override
  String activityMedicinesRecorded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count medicines recorded',
      one: '1 medicine recorded',
    );
    return '$_temp0';
  }

  @override
  String get activityAnalysed => 'Analysed';

  @override
  String get activityProcessing => 'Processing';

  @override
  String insightMedicineFlaggedTitle(String name, String strength) {
    return '$name $strength flagged';
  }

  @override
  String get insightMedicineFlaggedDefaultSubtitle => 'Tap to view details';

  @override
  String get insightReportDefaultSubtitle => 'Review the analysis';

  @override
  String get insightWearableHrTitle => 'Resting heart rate elevated';

  @override
  String insightWearableHrSubtitle(int bpm) {
    return '$bpm bpm today — worth mentioning at your next check-in.';
  }

  @override
  String get insightWearableSleepTitle => 'Short sleep last night';

  @override
  String insightWearableSleepSubtitle(String hours) {
    return 'Only ${hours}h logged — sleep affects blood pressure and glucose control.';
  }

  @override
  String insightGenericSwapTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Generic swaps available for $count medicines',
      one: 'Generic swap available',
    );
    return '$_temp0';
  }

  @override
  String insightGenericSwapSubtitle(
      String savingsLabel, String brandName, String genericName) {
    return 'Save $savingsLabel switching $brandName to $genericName — see Generic Swap.';
  }

  @override
  String insightRecentScanTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Recent scan · $count medicines',
      one: 'Recent scan · 1 medicine',
    );
    return '$_temp0';
  }

  @override
  String insightRecentScanSubtitleCaptured(String date) {
    return 'Captured $date';
  }

  @override
  String get insightRecentScanSubtitleTapToView => 'Tap to view';

  @override
  String get insightCorrelatedBadge => 'Correlated';

  @override
  String get insightCorrelatedAdherenceVitalsTitle =>
      'Adherence drop may be affecting your vitals';

  @override
  String insightCorrelatedAdherenceVitalsSubtitle(
      int percent, String vitalLabel) {
    return 'Your medicine adherence averaged $percent% over the last two weeks, and your $vitalLabel has been trending up in the same window — worth flagging at your next visit.';
  }

  @override
  String get insightCorrelatedVitalsReportTitle =>
      'Vitals trend confirmed by your latest labs';

  @override
  String insightCorrelatedVitalsReportSubtitle(
      String vitalLabel, String metricLabel) {
    return 'Your $vitalLabel has been rising, and your recent report\'s $metricLabel is also out of range — the two line up.';
  }

  @override
  String get insightCorrelatedWearableVitalsTitle => 'A pattern worth watching';

  @override
  String insightCorrelatedWearableVitalsSubtitle(
      String vitalLabel, String wearableSignalLabel) {
    String _temp0 = intl.Intl.selectLogic(
      wearableSignalLabel,
      {
        'sleep': 'sleep',
        'heartRate': 'heart rate',
        'other': 'activity',
      },
    );
    return 'Your $vitalLabel was out of range around the same time your wearable logged unusual $_temp0.';
  }

  @override
  String get healthTimelineTitle => 'Health timeline';

  @override
  String get healthTimelineViewFullLink => 'View full timeline';

  @override
  String get healthTimelineEmptyState =>
      'Nothing logged yet. Scan a prescription, upload a report, or log a vital to start building your timeline.';

  @override
  String get timelineLabelMedicine => 'Medicine';

  @override
  String get timelineLabelReport => 'Report';

  @override
  String get timelineLabelMetric => 'Metric';

  @override
  String get timelineLabelSleep => 'Sleep';

  @override
  String get timelineLabelRestingHeartRate => 'Resting heart rate';

  @override
  String get timelineLabelAdherence => 'Adherence';
}
