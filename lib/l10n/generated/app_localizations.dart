import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('ta')
  ];

  /// Bottom nav / side rail label
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navAssistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get navAssistant;

  /// No description provided for @navScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get navScan;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Health dashboard'**
  String get dashboardTitle;

  /// No description provided for @dashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Synced with your medical records'**
  String get dashboardSubtitle;

  /// No description provided for @statMedicines.
  ///
  /// In en, this message translates to:
  /// **'Medicines'**
  String get statMedicines;

  /// No description provided for @statAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get statAlerts;

  /// No description provided for @statAllClear.
  ///
  /// In en, this message translates to:
  /// **'All clear'**
  String get statAllClear;

  /// No description provided for @statReviewNow.
  ///
  /// In en, this message translates to:
  /// **'Review now'**
  String get statReviewNow;

  /// No description provided for @statScansCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 scans} =1{1 scan} other{{count} scans}}'**
  String statScansCount(int count);

  /// No description provided for @quickActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActionsTitle;

  /// No description provided for @quickActionMedicineReminder.
  ///
  /// In en, this message translates to:
  /// **'Medicine\nReminder'**
  String get quickActionMedicineReminder;

  /// No description provided for @quickActionNearbyPharmacies.
  ///
  /// In en, this message translates to:
  /// **'Nearby\nPharmacies'**
  String get quickActionNearbyPharmacies;

  /// No description provided for @quickActionHealthRisk.
  ///
  /// In en, this message translates to:
  /// **'Health Risk\nInsights'**
  String get quickActionHealthRisk;

  /// No description provided for @quickActionEmergencyContacts.
  ///
  /// In en, this message translates to:
  /// **'Emergency\nContacts'**
  String get quickActionEmergencyContacts;

  /// No description provided for @quickActionGenericSwap.
  ///
  /// In en, this message translates to:
  /// **'Generic\nSwap'**
  String get quickActionGenericSwap;

  /// No description provided for @nextDoseLabel.
  ///
  /// In en, this message translates to:
  /// **'NEXT DOSE'**
  String get nextDoseLabel;

  /// No description provided for @nextDoseNone.
  ///
  /// In en, this message translates to:
  /// **'No pending reminders'**
  String get nextDoseNone;

  /// No description provided for @nextDoseClear.
  ///
  /// In en, this message translates to:
  /// **'Everything is clear'**
  String get nextDoseClear;

  /// No description provided for @adherenceStreak.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{No active streak} =1{1-day streak} other{{days}-day streak}}'**
  String adherenceStreak(int days);

  /// No description provided for @adherenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Adherence'**
  String get adherenceLabel;

  /// No description provided for @adherenceNoData.
  ///
  /// In en, this message translates to:
  /// **'No adherence data yet'**
  String get adherenceNoData;

  /// No description provided for @adherenceNoDataHint.
  ///
  /// In en, this message translates to:
  /// **'Mark doses taken or missed to start a streak.'**
  String get adherenceNoDataHint;

  /// No description provided for @recentActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivityTitle;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @noActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get noActivityTitle;

  /// No description provided for @noActivityHint.
  ///
  /// In en, this message translates to:
  /// **'Scan a prescription or upload a report to get started.'**
  String get noActivityHint;

  /// No description provided for @noNewNotifications.
  ///
  /// In en, this message translates to:
  /// **'No new notifications'**
  String get noNewNotifications;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'{label} — coming soon'**
  String comingSoon(String label);

  /// No description provided for @doseSlotMorning.
  ///
  /// In en, this message translates to:
  /// **'Morning dose'**
  String get doseSlotMorning;

  /// No description provided for @doseSlotAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Afternoon dose'**
  String get doseSlotAfternoon;

  /// No description provided for @doseSlotNight.
  ///
  /// In en, this message translates to:
  /// **'Night dose'**
  String get doseSlotNight;

  /// No description provided for @activityPrescriptionScan.
  ///
  /// In en, this message translates to:
  /// **'Prescription scan'**
  String get activityPrescriptionScan;

  /// No description provided for @activityMedicinesRecorded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 medicine recorded} other{{count} medicines recorded}}'**
  String activityMedicinesRecorded(int count);

  /// No description provided for @activityAnalysed.
  ///
  /// In en, this message translates to:
  /// **'Analysed'**
  String get activityAnalysed;

  /// No description provided for @activityProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get activityProcessing;

  /// No description provided for @insightMedicineFlaggedTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} {strength} flagged'**
  String insightMedicineFlaggedTitle(String name, String strength);

  /// No description provided for @insightMedicineFlaggedDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to view details'**
  String get insightMedicineFlaggedDefaultSubtitle;

  /// No description provided for @insightReportDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review the analysis'**
  String get insightReportDefaultSubtitle;

  /// No description provided for @insightWearableHrTitle.
  ///
  /// In en, this message translates to:
  /// **'Resting heart rate elevated'**
  String get insightWearableHrTitle;

  /// No description provided for @insightWearableHrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{bpm} bpm today — worth mentioning at your next check-in.'**
  String insightWearableHrSubtitle(int bpm);

  /// No description provided for @insightWearableSleepTitle.
  ///
  /// In en, this message translates to:
  /// **'Short sleep last night'**
  String get insightWearableSleepTitle;

  /// No description provided for @insightWearableSleepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only {hours}h logged — sleep affects blood pressure and glucose control.'**
  String insightWearableSleepSubtitle(String hours);

  /// No description provided for @insightGenericSwapTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Generic swap available} other{Generic swaps available for {count} medicines}}'**
  String insightGenericSwapTitle(int count);

  /// No description provided for @insightGenericSwapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save {savingsLabel} switching {brandName} to {genericName} — see Generic Swap.'**
  String insightGenericSwapSubtitle(
      String savingsLabel, String brandName, String genericName);

  /// No description provided for @insightRecentScanTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Recent scan · 1 medicine} other{Recent scan · {count} medicines}}'**
  String insightRecentScanTitle(int count);

  /// No description provided for @insightRecentScanSubtitleCaptured.
  ///
  /// In en, this message translates to:
  /// **'Captured {date}'**
  String insightRecentScanSubtitleCaptured(String date);

  /// No description provided for @insightRecentScanSubtitleTapToView.
  ///
  /// In en, this message translates to:
  /// **'Tap to view'**
  String get insightRecentScanSubtitleTapToView;

  /// No description provided for @insightCorrelatedBadge.
  ///
  /// In en, this message translates to:
  /// **'Correlated'**
  String get insightCorrelatedBadge;

  /// No description provided for @insightCorrelatedAdherenceVitalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Adherence drop may be affecting your vitals'**
  String get insightCorrelatedAdherenceVitalsTitle;

  /// No description provided for @insightCorrelatedAdherenceVitalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your medicine adherence averaged {percent}% over the last two weeks, and your {vitalLabel} has been trending up in the same window — worth flagging at your next visit.'**
  String insightCorrelatedAdherenceVitalsSubtitle(
      int percent, String vitalLabel);

  /// No description provided for @insightCorrelatedVitalsReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Vitals trend confirmed by your latest labs'**
  String get insightCorrelatedVitalsReportTitle;

  /// No description provided for @insightCorrelatedVitalsReportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your {vitalLabel} has been rising, and your recent report\'s {metricLabel} is also out of range — the two line up.'**
  String insightCorrelatedVitalsReportSubtitle(
      String vitalLabel, String metricLabel);

  /// No description provided for @insightCorrelatedWearableVitalsTitle.
  ///
  /// In en, this message translates to:
  /// **'A pattern worth watching'**
  String get insightCorrelatedWearableVitalsTitle;

  /// No description provided for @insightCorrelatedWearableVitalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your {vitalLabel} was out of range around the same time your wearable logged unusual {wearableSignalLabel, select, sleep{sleep} heartRate{heart rate} other{activity}}.'**
  String insightCorrelatedWearableVitalsSubtitle(
      String vitalLabel, String wearableSignalLabel);

  /// No description provided for @healthTimelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Health timeline'**
  String get healthTimelineTitle;

  /// No description provided for @healthTimelineViewFullLink.
  ///
  /// In en, this message translates to:
  /// **'View full timeline'**
  String get healthTimelineViewFullLink;

  /// No description provided for @healthTimelineEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged yet. Scan a prescription, upload a report, or log a vital to start building your timeline.'**
  String get healthTimelineEmptyState;

  /// No description provided for @timelineLabelMedicine.
  ///
  /// In en, this message translates to:
  /// **'Medicine'**
  String get timelineLabelMedicine;

  /// No description provided for @timelineLabelReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get timelineLabelReport;

  /// No description provided for @timelineLabelMetric.
  ///
  /// In en, this message translates to:
  /// **'Metric'**
  String get timelineLabelMetric;

  /// No description provided for @timelineLabelSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get timelineLabelSleep;

  /// No description provided for @timelineLabelRestingHeartRate.
  ///
  /// In en, this message translates to:
  /// **'Resting heart rate'**
  String get timelineLabelRestingHeartRate;

  /// No description provided for @timelineLabelAdherence.
  ///
  /// In en, this message translates to:
  /// **'Adherence'**
  String get timelineLabelAdherence;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'ta':
      return AppLocalizationsTa();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
