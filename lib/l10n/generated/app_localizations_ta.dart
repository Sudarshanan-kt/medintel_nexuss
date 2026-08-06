// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get navHome => 'முகப்பு';

  @override
  String get navAssistant => 'உதவியாளர்';

  @override
  String get navScan => 'ஸ்கேன்';

  @override
  String get navReports => 'அறிக்கைகள்';

  @override
  String get navProfile => 'சுயவிவரம்';

  @override
  String get dashboardTitle => 'சுகாதார டாஷ்போர்டு';

  @override
  String get dashboardSubtitle =>
      'உங்கள் மருத்துவ பதிவுகளுடன் ஒத்திசைக்கப்பட்டது';

  @override
  String get statMedicines => 'மருந்துகள்';

  @override
  String get statAlerts => 'எச்சரிக்கைகள்';

  @override
  String get statAllClear => 'எல்லாம் சரி';

  @override
  String get statReviewNow => 'இப்போது பாருங்கள்';

  @override
  String statScansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ஸ்கேன்கள்',
      one: '1 ஸ்கேன்',
      zero: '0 ஸ்கேன்கள்',
    );
    return '$_temp0';
  }

  @override
  String get quickActionsTitle => 'விரைவு செயல்கள்';

  @override
  String get quickActionMedicineReminder => 'மருந்து\nநினைவூட்டல்';

  @override
  String get quickActionNearbyPharmacies => 'அருகிலுள்ள\nமருந்தகங்கள்';

  @override
  String get quickActionHealthRisk => 'சுகாதார ரிஸ்க்\nநுண்ணறிவு';

  @override
  String get quickActionEmergencyContacts => 'அவசர\nதொடர்புகள்';

  @override
  String get quickActionGenericSwap => 'ஜெனரிக்\nமாற்று';

  @override
  String get nextDoseLabel => 'அடுத்த டோஸ்';

  @override
  String get nextDoseNone => 'நினைவூட்டல்கள் இல்லை';

  @override
  String get nextDoseClear => 'எல்லாம் சரியாக உள்ளது';

  @override
  String adherenceStreak(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days நாள் தொடர்ச்சி',
      one: '1 நாள் தொடர்ச்சி',
      zero: 'செயலில் உள்ள தொடர்ச்சி இல்லை',
    );
    return '$_temp0';
  }

  @override
  String get adherenceLabel => 'கடைப்பிடிப்பு';

  @override
  String get adherenceNoData => 'இன்னும் கடைப்பிடிப்பு தரவு இல்லை';

  @override
  String get adherenceNoDataHint =>
      'தொடர்ச்சியைத் தொடங்க டோஸை எடுத்தேன் அல்லது தவறவிட்டேன் என குறிக்கவும்.';

  @override
  String get recentActivityTitle => 'சமீபத்திய செயல்பாடு';

  @override
  String get viewAll => 'அனைத்தையும் காண்க';

  @override
  String get noActivityTitle => 'இன்னும் செயல்பாடு இல்லை';

  @override
  String get noActivityHint =>
      'தொடங்க ஒரு மருந்துச்சீட்டை ஸ்கேன் செய்யவும் அல்லது அறிக்கையை பதிவேற்றவும்.';

  @override
  String get noNewNotifications => 'புதிய அறிவிப்புகள் இல்லை';

  @override
  String comingSoon(String label) {
    return '$label — விரைவில் வரும்';
  }

  @override
  String get doseSlotMorning => 'காலை டோஸ்';

  @override
  String get doseSlotAfternoon => 'மதிய டோஸ்';

  @override
  String get doseSlotNight => 'இரவு டோஸ்';

  @override
  String get activityPrescriptionScan => 'மருந்துச்சீட்டு ஸ்கேன்';

  @override
  String activityMedicinesRecorded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count மருந்துகள் பதிவு செய்யப்பட்டன',
      one: '1 மருந்து பதிவு செய்யப்பட்டது',
    );
    return '$_temp0';
  }

  @override
  String get activityAnalysed => 'பகுப்பாய்வு முடிந்தது';

  @override
  String get activityProcessing => 'செயலாக்கத்தில்';

  @override
  String insightMedicineFlaggedTitle(String name, String strength) {
    return '$name $strength கொடிமிட்டப்பட்டது';
  }

  @override
  String get insightMedicineFlaggedDefaultSubtitle =>
      'விவரங்களைக் காண தட்டவும்';

  @override
  String get insightReportDefaultSubtitle => 'பகுப்பாய்வைப் பார்க்கவும்';

  @override
  String get insightWearableHrTitle => 'ஓய்வு இதய துடிப்பு அதிகரித்துள்ளது';

  @override
  String insightWearableHrSubtitle(int bpm) {
    return 'இன்று $bpm bpm — உங்கள் அடுத்த சந்திப்பில் இதைக் குறிப்பிடவும்.';
  }

  @override
  String get insightWearableSleepTitle => 'நேற்று இரவு குறைவான தூக்கம்';

  @override
  String insightWearableSleepSubtitle(String hours) {
    return '$hours மணி நேரம் மட்டுமே பதிவு — தூக்கம் இரத்த அழுத்தம் மற்றும் இரத்த சர்க்கரையை பாதிக்கிறது.';
  }

  @override
  String insightGenericSwapTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count மருந்துகளுக்கு ஜெனரிக் மாற்று கிடைக்கிறது',
      one: 'ஜெனரிக் மாற்று கிடைக்கிறது',
    );
    return '$_temp0';
  }

  @override
  String insightGenericSwapSubtitle(
      String savingsLabel, String brandName, String genericName) {
    return '$brandName இலிருந்து $genericName க்கு மாறி $savingsLabel சேமிக்கவும் — ஜெனரிக் மாற்றைப் பார்க்கவும்.';
  }

  @override
  String insightRecentScanTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'சமீபத்திய ஸ்கேன் · $count மருந்துகள்',
      one: 'சமீபத்திய ஸ்கேன் · 1 மருந்து',
    );
    return '$_temp0';
  }

  @override
  String insightRecentScanSubtitleCaptured(String date) {
    return '$date அன்று படமெடுக்கப்பட்டது';
  }

  @override
  String get insightRecentScanSubtitleTapToView => 'பார்க்க தட்டவும்';

  @override
  String get insightCorrelatedBadge => 'தொடர்புடையது';

  @override
  String get insightCorrelatedAdherenceVitalsTitle =>
      'மருந்து தவறியது உங்கள் உயிர் அளவீடுகளை பாதிக்கலாம்';

  @override
  String insightCorrelatedAdherenceVitalsSubtitle(
      int percent, String vitalLabel) {
    return 'கடந்த இரண்டு வாரங்களில் உங்கள் மருந்து கடைப்பிடிப்பு சராசரியாக $percent% ஆக இருந்தது, அதே காலகட்டத்தில் உங்கள் $vitalLabel அதிகரித்து வருகிறது — உங்கள் அடுத்த சந்திப்பில் இதைக் குறிப்பிடவும்.';
  }

  @override
  String get insightCorrelatedVitalsReportTitle =>
      'உங்கள் உயிர் அளவீட்டு போக்கு புதிய அறிக்கையுடன் பொருந்துகிறது';

  @override
  String insightCorrelatedVitalsReportSubtitle(
      String vitalLabel, String metricLabel) {
    return 'உங்கள் $vitalLabel உயர்ந்து வருகிறது, மேலும் உங்கள் சமீபத்திய அறிக்கையில் $metricLabel இயல்பு வரம்பிற்கு வெளியே உள்ளது — இரண்டும் ஒத்துப்போகின்றன.';
  }

  @override
  String get insightCorrelatedWearableVitalsTitle => 'கவனிக்க வேண்டிய ஒரு முறை';

  @override
  String insightCorrelatedWearableVitalsSubtitle(
      String vitalLabel, String wearableSignalLabel) {
    String _temp0 = intl.Intl.selectLogic(
      wearableSignalLabel,
      {
        'sleep': 'தூக்கத்தை',
        'heartRate': 'இதய துடிப்பை',
        'other': 'செயல்பாட்டை',
      },
    );
    return 'உங்கள் $vitalLabel இயல்பு வரம்பிற்கு வெளியே இருந்த அதே நேரத்தில், உங்கள் வேரபிள் சாதனம் அசாதாரண $_temp0 பதிவு செய்தது.';
  }

  @override
  String get healthTimelineTitle => 'சுகாதார காலவரிசை';

  @override
  String get healthTimelineViewFullLink => 'முழு காலவரிசையைக் காண்க';

  @override
  String get healthTimelineEmptyState =>
      'இன்னும் எதுவும் பதிவு செய்யப்படவில்லை. உங்கள் காலவரிசையைத் தொடங்க ஒரு மருந்துச்சீட்டை ஸ்கேன் செய்யவும், அறிக்கையை பதிவேற்றவும் அல்லது ஒரு உயிர் அளவீட்டைப் பதிவு செய்யவும்.';

  @override
  String get timelineLabelMedicine => 'மருந்து';

  @override
  String get timelineLabelReport => 'அறிக்கை';

  @override
  String get timelineLabelMetric => 'அளவீடு';

  @override
  String get timelineLabelSleep => 'தூக்கம்';

  @override
  String get timelineLabelRestingHeartRate => 'ஓய்வு இதய துடிப்பு';

  @override
  String get timelineLabelAdherence => 'கடைப்பிடிப்பு';
}
