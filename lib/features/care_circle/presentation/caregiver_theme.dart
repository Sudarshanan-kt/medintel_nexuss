/// Caregiver identity — violet, matching the caregiver sign-in screen.
///
/// The whole point of the colour split is that someone who looks after a
/// parent can tell at a glance whose data they're looking at. Kept local to
/// the feature for the same reason the patient dashboard keeps its mint
/// tokens local.
library;

import 'package:flutter/material.dart';

const Color kBg = Color(0xFFF4F1FC);
const Color kViolet = Color(0xFF7C5CFC);
const Color kVioletLight = Color(0xFFB6A4FF);
const Color kVioletDeep = Color(0xFF5B3FD9);
const Color kVioletSoft = Color(0xFFEEE9FE);
const Color kInk = Color(0xFF241E3B);
const Color kMuted = Color(0xFF6B6382);
const Color kCard = Colors.white;
const Color kCardStroke = Color(0xFFEBE6F7);
const Color kAmber = Color(0xFF9A6206);
const Color kRed = Color(0xFFC63A30);
const Color kGreenOk = Color(0xFF0C7D5D);

const LinearGradient kCaregiverGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kVioletLight, kVioletDeep],
);

/// Type scale.
///
/// Larger than the patient side on purpose. The people using this screen are
/// disproportionately older than the patients they look after, and the
/// smallest text here was 11px — below what Material recommends as a floor
/// for anything a user is expected to read rather than glance past. Nothing
/// is under 13 now, and body copy sits at 15.
const TextStyle kTitle =
    TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk);
const TextStyle kCardTitle =
    TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk);
const TextStyle kBody = TextStyle(fontSize: 15, color: kInk, height: 1.35);
const TextStyle kBodyMuted =
    TextStyle(fontSize: 14.5, color: kMuted, height: 1.35);
const TextStyle kLabel =
    TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kMuted);
const TextStyle kMetric =
    TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kInk);

/// Minimum tappable size. Material's floor is 48; care actions get it
/// explicitly because several of them are icon-only.
const double kTapTarget = 48;

BoxDecoration cardDecoration({Color? stroke}) => BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: stroke ?? kCardStroke),
    );

/// Adherence colour, and — always alongside it — a word.
///
/// Roughly 1 in 12 men has some red/green colour deficiency, and the three
/// states this app cares about were encoded as green, amber and red with no
/// other distinguishing mark. Every caller of [adherenceTone] is expected to
/// render [adherenceWord] next to whatever it colours.
Color adherenceTone(double percent, {required bool hasData}) {
  if (!hasData) return kMuted;
  if (percent >= 80) return kGreenOk;
  if (percent >= 50) return kAmber;
  return kRed;
}

String adherenceWord(double percent, {required bool hasData}) {
  if (!hasData) return 'Not tracked';
  if (percent >= 80) return 'On track';
  if (percent >= 50) return 'Slipping';
  return 'Needs attention';
}
