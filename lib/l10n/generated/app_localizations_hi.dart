// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get navHome => 'होम';

  @override
  String get navAssistant => 'सहायक';

  @override
  String get navScan => 'स्कैन';

  @override
  String get navReports => 'रिपोर्ट';

  @override
  String get navProfile => 'प्रोफ़ाइल';

  @override
  String get dashboardTitle => 'स्वास्थ्य डैशबोर्ड';

  @override
  String get dashboardSubtitle => 'आपके मेडिकल रिकॉर्ड के साथ सिंक किया गया';

  @override
  String get statMedicines => 'दवाइयाँ';

  @override
  String get statAlerts => 'अलर्ट';

  @override
  String get statAllClear => 'सब ठीक है';

  @override
  String get statReviewNow => 'अभी देखें';

  @override
  String statScansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count स्कैन',
      one: '1 स्कैन',
      zero: '0 स्कैन',
    );
    return '$_temp0';
  }

  @override
  String get quickActionsTitle => 'त्वरित कार्य';

  @override
  String get quickActionMedicineReminder => 'दवा\nरिमाइंडर';

  @override
  String get quickActionNearbyPharmacies => 'नज़दीकी\nफार्मेसी';

  @override
  String get quickActionHealthRisk => 'स्वास्थ्य जोखिम\nजानकारी';

  @override
  String get quickActionEmergencyContacts => 'आपातकालीन\nसंपर्क';

  @override
  String get quickActionGenericSwap => 'जेनेरिक\nस्वैप';

  @override
  String get nextDoseLabel => 'अगली खुराक';

  @override
  String get nextDoseNone => 'कोई रिमाइंडर नहीं';

  @override
  String get nextDoseClear => 'सब कुछ ठीक है';

  @override
  String adherenceStreak(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days दिन की स्ट्रीक',
      one: '1 दिन की स्ट्रीक',
      zero: 'कोई सक्रिय स्ट्रीक नहीं',
    );
    return '$_temp0';
  }

  @override
  String get adherenceLabel => 'पालन';

  @override
  String get adherenceNoData => 'अभी तक कोई डेटा नहीं';

  @override
  String get adherenceNoDataHint =>
      'स्ट्रीक शुरू करने के लिए खुराक को लिया या छूटा हुआ चिह्नित करें।';

  @override
  String get recentActivityTitle => 'हाल की गतिविधि';

  @override
  String get viewAll => 'सभी देखें';

  @override
  String get noActivityTitle => 'अभी तक कोई गतिविधि नहीं';

  @override
  String get noActivityHint =>
      'शुरू करने के लिए एक पर्ची स्कैन करें या रिपोर्ट अपलोड करें।';

  @override
  String get noNewNotifications => 'कोई नया नोटिफिकेशन नहीं';

  @override
  String comingSoon(String label) {
    return '$label — जल्द आ रहा है';
  }

  @override
  String get doseSlotMorning => 'सुबह की खुराक';

  @override
  String get doseSlotAfternoon => 'दोपहर की खुराक';

  @override
  String get doseSlotNight => 'रात की खुराक';

  @override
  String get activityPrescriptionScan => 'पर्ची स्कैन';

  @override
  String activityMedicinesRecorded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दवाइयाँ दर्ज की गईं',
      one: '1 दवा दर्ज की गई',
    );
    return '$_temp0';
  }

  @override
  String get activityAnalysed => 'विश्लेषण हो गया';

  @override
  String get activityProcessing => 'प्रोसेसिंग हो रही है';

  @override
  String insightMedicineFlaggedTitle(String name, String strength) {
    return '$name $strength फ़्लैग किया गया';
  }

  @override
  String get insightMedicineFlaggedDefaultSubtitle =>
      'विवरण देखने के लिए टैप करें';

  @override
  String get insightReportDefaultSubtitle => 'विश्लेषण देखें';

  @override
  String get insightWearableHrTitle => 'आराम की हृदय गति बढ़ी हुई है';

  @override
  String insightWearableHrSubtitle(int bpm) {
    return 'आज $bpm bpm — अगली जांच में इसका ज़िक्र करें।';
  }

  @override
  String get insightWearableSleepTitle => 'पिछली रात कम नींद';

  @override
  String insightWearableSleepSubtitle(String hours) {
    return 'सिर्फ़ $hours घंटे दर्ज — नींद रक्तचाप और रक्त शर्करा को प्रभावित करती है।';
  }

  @override
  String insightGenericSwapTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दवाइयों के लिए जेनेरिक विकल्प उपलब्ध हैं',
      one: 'जेनेरिक विकल्प उपलब्ध है',
    );
    return '$_temp0';
  }

  @override
  String insightGenericSwapSubtitle(
      String savingsLabel, String brandName, String genericName) {
    return '$brandName से $genericName पर स्विच करके $savingsLabel बचाएं — जेनेरिक स्वैप देखें।';
  }

  @override
  String insightRecentScanTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'हाल की स्कैन · $count दवाइयाँ',
      one: 'हाल की स्कैन · 1 दवा',
    );
    return '$_temp0';
  }

  @override
  String insightRecentScanSubtitleCaptured(String date) {
    return '$date को कैप्चर किया गया';
  }

  @override
  String get insightRecentScanSubtitleTapToView => 'देखने के लिए टैप करें';

  @override
  String get insightCorrelatedBadge => 'संबंधित';

  @override
  String get insightCorrelatedAdherenceVitalsTitle =>
      'दवा न लेने का असर आपके वाइटल्स पर पड़ सकता है';

  @override
  String insightCorrelatedAdherenceVitalsSubtitle(
      int percent, String vitalLabel) {
    return 'पिछले दो हफ़्तों में आपका दवा पालन औसतन $percent% रहा, और इसी अवधि में आपका $vitalLabel बढ़ता दिख रहा है — अगली मुलाकात में डॉक्टर को बताएं।';
  }

  @override
  String get insightCorrelatedVitalsReportTitle =>
      'आपके वाइटल्स की प्रवृत्ति नई रिपोर्ट से भी मेल खाती है';

  @override
  String insightCorrelatedVitalsReportSubtitle(
      String vitalLabel, String metricLabel) {
    return 'आपका $vitalLabel बढ़ रहा है, और आपकी हाल की रिपोर्ट में $metricLabel भी सामान्य सीमा से बाहर है — दोनों मेल खाते हैं।';
  }

  @override
  String get insightCorrelatedWearableVitalsTitle =>
      'ध्यान देने लायक एक पैटर्न';

  @override
  String insightCorrelatedWearableVitalsSubtitle(
      String vitalLabel, String wearableSignalLabel) {
    String _temp0 = intl.Intl.selectLogic(
      wearableSignalLabel,
      {
        'sleep': 'नींद',
        'heartRate': 'हृदय गति',
        'other': 'गतिविधि',
      },
    );
    return 'जिस समय आपका $vitalLabel सामान्य सीमा से बाहर था, उसी समय आपके वियरेबल ने असामान्य $_temp0 दर्ज की।';
  }

  @override
  String get healthTimelineTitle => 'स्वास्थ्य समयरेखा';

  @override
  String get healthTimelineViewFullLink => 'पूरी समयरेखा देखें';

  @override
  String get healthTimelineEmptyState =>
      'अभी तक कुछ दर्ज नहीं है। अपनी समयरेखा शुरू करने के लिए पर्ची स्कैन करें, रिपोर्ट अपलोड करें, या कोई वाइटल दर्ज करें।';

  @override
  String get timelineLabelMedicine => 'दवा';

  @override
  String get timelineLabelReport => 'रिपोर्ट';

  @override
  String get timelineLabelMetric => 'मेट्रिक';

  @override
  String get timelineLabelSleep => 'नींद';

  @override
  String get timelineLabelRestingHeartRate => 'आराम की हृदय गति';

  @override
  String get timelineLabelAdherence => 'पालन';
}
