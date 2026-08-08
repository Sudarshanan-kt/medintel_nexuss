import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../profile/application/profile_controller.dart';
import '../../profile/domain/profile_record.dart';
import '../data/sos_native_channel.dart';
import '../data/sos_repository.dart';
import '../domain/emergency_event.dart';

/// State for the Emergency SOS Controller.
class SosState {
  const SosState({
    this.events = const [],
    this.customMessage = '',
    this.isTriggering = false,
  });

  final List<EmergencyEvent> events;
  final String customMessage;
  final bool isTriggering;

  SosState copyWith({
    List<EmergencyEvent>? events,
    String? customMessage,
    bool? isTriggering,
  }) =>
      SosState(
        events: events ?? this.events,
        customMessage: customMessage ?? this.customMessage,
        isTriggering: isTriggering ?? this.isTriggering,
      );
}

/// Controller managing Emergency SOS activation, GPS location fetching,
/// phone calls, SMS dispatch, WhatsApp messaging, contact management,
/// and dual-layer event persistence.
class SosController extends Notifier<SosState> {
  static const _cacheKey = 'medintel_sos_events_v1';
  static const _msgKey = 'medintel_sos_custom_msg_v1';

  void _log(String msg) => dev.log(msg, name: 'sos.controller');

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  SosRepository get _repo => ref.read(sosRepositoryProvider);
  SosNativeChannel get _native => ref.read(sosNativeChannelProvider);

  @override
  SosState build() {
    _restore();
    return const SosState();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMsg = prefs.getString(_msgKey) ?? '';
      final rawEvents = prefs.getString(_cacheKey);

      List<EmergencyEvent> localEvents = [];
      if (rawEvents != null && rawEvents.isNotEmpty) {
        localEvents = (jsonDecode(rawEvents) as List)
            .cast<Map<String, dynamic>>()
            .map(EmergencyEvent.fromJson)
            .toList();
      }

      state = SosState(events: localEvents, customMessage: savedMsg);
      await _restoreRemote();
    } catch (e) {
      _log('restore error: $e');
    }
  }

  Future<void> _restoreRemote() async {
    try {
      final userId = _userId;
      if (userId == null) return;

      final remote = await _repo.fetchAllEvents(userId);
      if (remote.isEmpty) return;

      final remoteById = {for (final e in remote) e.id: e};
      final localOnly =
          state.events.where((e) => !remoteById.containsKey(e.id)).toList();

      state = state.copyWith(events: [...remote, ...localOnly]);
      await _saveLocal();
    } catch (e) {
      _log('remote restore error: $e');
    }
  }

  void _persistLocal() {
    final snap = state;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _cacheKey,
          jsonEncode(snap.events.map((e) => e.toJson()).toList()),
        );
        await prefs.setString(_msgKey, snap.customMessage);
      } catch (e) {
        _log('persistLocal error: $e');
      }
    }());
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(state.events.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  void _upsertRemote(EmergencyEvent event) {
    final userId = _userId;
    if (userId == null) return;
    unawaited(
      _repo
          .upsertEvent(userId, event)
          .timeout(const Duration(seconds: 8))
          .catchError((Object e) => _log('upsertRemote error: $e')),
    );
  }

  // ── GPS Location Resolver ──────────────────────────────────────────────────

  Future<Position?> _getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      _log('GPS location fetch failed gracefully: $e');
      return null;
    }
  }

  // ── SOS Dispatch Actions ───────────────────────────────────────────────────

  /// True once the user has granted the Android SEND_SMS + CALL_PHONE
  /// permissions that make SMS/calling fully automatic (see
  /// `SosNativeChannel`). Elsewhere (iOS/web, or before granting), dispatch
  /// silently falls back to the tap-to-send paths further below.
  Future<bool> hasAutomaticDispatchPermissions() => _native.hasPermissions();

  /// Prompts for those permissions. Returns whether both were granted.
  Future<bool> requestAutomaticDispatchPermissions() =>
      _native.requestPermissions();

  /// Triggers full Emergency SOS dispatch after 3-second countdown elapses.
  Future<EmergencyEvent> triggerSos() async {
    state = state.copyWith(isTriggering: true);

    // 1. Get emergency contacts from profile
    final profile = ref.read(profileControllerProvider);
    final contacts = profile.emergencyContacts;

    // Resolve primary contact — with no fallback number: a hardcoded
    // country-specific emergency number (e.g. '911') would silently be
    // wrong for most of this app's actual users, so with no contact set
    // this simply doesn't attempt a call rather than dialing a number that
    // isn't even valid for the user's country.
    EmergencyContact? primary;
    if (contacts.isNotEmpty) {
      primary =
          contacts.firstWhere((c) => c.isPrimary, orElse: () => contacts.first);
    }

    // 2. Fetch current GPS location
    final position = await _getCurrentLocation();
    final lat = position?.latitude;
    final lng = position?.longitude;

    // 3. Build emergency message text
    final patientName = profile.personal.fullName.isNotEmpty
        ? profile.personal.fullName
        : 'MedIntel Patient';
    final locationText = (lat != null && lng != null)
        ? 'Location: https://maps.google.com/?q=$lat,$lng'
        : 'Location: Unavailable';

    final baseMsg = state.customMessage.isNotEmpty
        ? state.customMessage
        : 'EMERGENCY SOS ALERT! $patientName needs immediate medical assistance.';
    final fullMsg = '$baseMsg\n$locationText';

    // 4. Create & persist event record
    final event = EmergencyEvent(
      id: 'sos_${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now(),
      latitude: lat,
      longitude: lng,
      primaryContactName: primary?.name ?? 'No contact set',
      primaryContactPhone: primary?.phone ?? '',
      message: fullMsg,
      status: 'triggered',
    );

    state = state.copyWith(
      events: [event, ...state.events],
      isTriggering: false,
    );
    _persistLocal();
    _upsertRemote(event);

    // 5. Call the primary contact — native silent ACTION_CALL first
    // (Android with permission granted), else the tap-to-dial fallback.
    if (primary != null && primary.phone.isNotEmpty) {
      final called = await _native.placeCall(primary.phone);
      if (!called) await makePhoneCall(primary.phone);
    }

    // 6. SMS every contact, then hand off to WhatsApp.
    //
    // SMS carries the emergency: on Android with the permission granted it
    // sends silently, and it goes carrier-to-carrier without passing
    // through anyone else. WhatsApp is a pre-filled deep link the user
    // taps.
    //
    // That last part used to be automatic, via a free third-party relay
    // (CallMeBot). It was removed: the message here carries the patient's
    // live coordinates and medical notes, and it was being handed to an
    // unaffiliated service in a plaintext query string. A second automatic
    // channel is not worth broadcasting someone's location and conditions
    // to a stranger, particularly when SMS already covers the zero-tap case.
    for (final contact in contacts) {
      if (contact.phone.isEmpty) continue;

      final smsSent =
          await _native.sendSms(phone: contact.phone, message: fullMsg);
      if (!smsSent) await sendSms(contact.phone, fullMsg);

      await openWhatsApp(contact.phone, fullMsg);
    }

    return event;
  }

  /// Initiates a phone call using url_launcher `tel:` — opens the dialer
  /// pre-filled; the user still has to tap call. Fallback for when the
  /// native silent path (see `SosNativeChannel.placeCall`) isn't available.
  Future<bool> makePhoneCall(String phoneNumber) async {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      } else {
        // Fallback to launch anyway
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _log('makePhoneCall error: $e');
      return false;
    }
  }

  /// Sends an SMS using url_launcher `sms:` — opens the composer
  /// pre-filled; the user still has to tap send. Fallback for when the
  /// native silent path (see `SosNativeChannel.sendSms`) isn't available.
  Future<bool> sendSms(String phoneNumber, String message) async {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final encodedMsg = Uri.encodeComponent(message);
    final uri = Uri.parse('sms:$cleaned?body=$encodedMsg');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      } else {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _log('sendSms error: $e');
      return false;
    }
  }

  /// Opens WhatsApp pre-filled with the emergency message
  /// (https://wa.me/phone?text=...) — the user still has to tap send.
  ///
  /// The link is handed to the OS, which hands it to the installed WhatsApp
  /// app; the message itself never travels through a web request from here.
  /// That is the whole reason this is the WhatsApp path rather than an
  /// automatic one — see the note in [triggerSos].
  Future<bool> openWhatsApp(String phoneNumber, String message) async {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    final encodedMsg = Uri.encodeComponent(message);
    final waUri = Uri.parse('https://wa.me/$cleaned?text=$encodedMsg');
    try {
      if (await canLaunchUrl(waUri)) {
        return await launchUrl(
          waUri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
      } else {
        return await launchUrl(waUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _log('openWhatsApp error: $e');
      return false;
    }
  }

  void setCustomMessage(String msg) {
    state = state.copyWith(customMessage: msg.trim());
    _persistLocal();
  }

  void deleteEvent(String id) {
    state = state.copyWith(
      events: state.events.where((e) => e.id != id).toList(),
    );
    _persistLocal();
    final userId = _userId;
    if (userId != null) {
      unawaited(_repo.deleteEvent(userId, id));
    }
  }
}

final sosControllerProvider =
    NotifierProvider<SosController, SosState>(SosController.new);
