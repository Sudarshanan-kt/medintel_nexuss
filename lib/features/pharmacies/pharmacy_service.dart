import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/network/api_endpoints.dart';
import '../../core/network/dio_client.dart';

/// A pharmacy / medical shop returned by OpenStreetMap (Overpass API).
class Pharmacy {
  Pharmacy({
    required this.name,
    required this.location,
    this.address,
    this.distanceMeters,
  });

  final String name;
  final LatLng location;
  final String? address;
  final double? distanceMeters;

  String get distanceLabel {
    final d = distanceMeters;
    if (d == null) return '';
    if (d < 1000) return '${d.round()} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }
}

/// Result bundle for the screen: the user's location plus nearby pharmacies.
class NearbyResult {
  NearbyResult({required this.center, required this.pharmacies});
  final LatLng center;
  final List<Pharmacy> pharmacies;
}

/// A search that couldn't be completed, carrying something worth showing the
/// user.
///
/// [toString] is the message alone, with no `Exception:` prefix, because the
/// screen renders it directly.
class PharmacySearchException implements Exception {
  const PharmacySearchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Finds real pharmacies around the user.
///
/// The device reads its own position and hands it to this app's backend,
/// which does the OpenStreetMap lookup on its behalf. It used to query
/// Overpass directly, which meant a patient's precise coordinates went to a
/// third party on every search; the backend now snaps them to a coarse grid
/// first, so what leaves the deployment is a neighbourhood rather than a
/// doorstep. See `app/routers/pharmacies.py`.
class PharmacyService {
  PharmacyService(this._dio);
  final Dio _dio;

  /// The patient's actual position, or an explanation of why there isn't one.
  ///
  /// This used to swallow every failure and quietly return Chennai city
  /// centre, so a denied permission or a switched-off GPS produced a map of
  /// real pharmacies hundreds of kilometres away, captioned as if they were
  /// nearby. Someone looking for a shop cannot tell that apart from a
  /// working search. Each failure now says what it is and what to do about
  /// it, which is the same posture as the rest of the app: no answer beats
  /// a confident wrong one.
  Future<LatLng> _resolveLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const PharmacySearchException(
        'Location is turned off on this phone, so there is nothing to search '
        'around. Turn it on and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const PharmacySearchException(
        'Location permission is blocked for MedIntel Nexus. Enable it in '
        'Settings → Apps → MedIntel Nexus → Permissions → Location, then '
        'try again.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const PharmacySearchException(
        'Finding pharmacies near you needs location permission. Allow it and '
        'try again.',
      );
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
      return LatLng(pos.latitude, pos.longitude);
    } on Object {
      throw const PharmacySearchException(
        "Couldn't get a location fix. Move somewhere with a clearer view of "
        'the sky, or try again in a moment.',
      );
    }
  }

  /// Searches for pharmacies within [radiusMeters] of the user.
  ///
  /// Throws on failure rather than returning an empty list — "we couldn't
  /// search" and "there are no pharmacies near you" are different things to
  /// tell someone looking for a shop, and the screen renders them
  /// differently.
  Future<NearbyResult> findNearby({double radiusMeters = 3000}) async {
    final center = await _resolveLocation();

    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get<Map<String, dynamic>>(
        ApiEndpoints.pharmaciesNearby,
        queryParameters: {
          'lat': center.latitude,
          'lon': center.longitude,
          'radius_m': radiusMeters.round(),
        },
        options: Options(receiveTimeout: const Duration(seconds: 40)),
      );
    } on DioException catch (e) {
      // The lookup runs on this app's backend so the patient's coordinates
      // aren't handed to a third party — which means no backend, no search.
      // Say so, rather than showing a raw DioException: "couldn't reach the
      // server" and "the search failed" send someone to different places.
      if (e.response == null) {
        throw const PharmacySearchException(
          "Couldn't reach the MedIntel server, so the pharmacy search "
          "couldn't run. Check that it's running and that this phone is on "
          'the same Wi-Fi as it.',
        );
      }
      throw const PharmacySearchException(
        'The pharmacy search failed on the server. Try again in a moment.',
      );
    }

    final data = res.data?['data'];
    if (data is! Map || data['searched'] != true) {
      throw const PharmacySearchException(
        'Pharmacy search is unavailable right now.',
      );
    }

    return NearbyResult(
      center: center,
      pharmacies: _parse(data['pharmacies'], center),
    );
  }

  /// The backend already sorted these by distance from the real position it
  /// was given, so this preserves order rather than re-sorting.
  List<Pharmacy> _parse(Object? raw, LatLng center) {
    if (raw is! List) return const [];
    final list = <Pharmacy>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final lat = (entry['lat'] as num?)?.toDouble();
      final lon = (entry['lon'] as num?)?.toDouble();
      final name = (entry['name'] as String?)?.trim();
      if (lat == null || lon == null || name == null || name.isEmpty) continue;

      list.add(
        Pharmacy(
          name: name,
          location: LatLng(lat, lon),
          address: (entry['address'] as String?)?.trim(),
          distanceMeters: (entry['distance_m'] as num?)?.toDouble(),
        ),
      );
    }
    return list;
  }
}

final pharmacyServiceProvider = Provider<PharmacyService>((ref) {
  return PharmacyService(ref.watch(dioClientProvider));
});

/// Loads nearby pharmacies once per screen visit.
final nearbyPharmaciesProvider = FutureProvider<NearbyResult>((ref) async {
  return ref.read(pharmacyServiceProvider).findNearby();
});
