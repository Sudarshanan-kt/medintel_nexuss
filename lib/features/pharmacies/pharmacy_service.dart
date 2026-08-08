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

  /// Default fallback location (used only if geolocation is denied/unavailable
  /// so the demo always shows something). Chennai city centre.
  static const _fallback = LatLng(13.0827, 80.2707);

  Future<LatLng> _resolveLocation() async {
    try {
      // Web + mobile: request permission then read position.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _fallback;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return _fallback;
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

    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.pharmaciesNearby,
      queryParameters: {
        'lat': center.latitude,
        'lon': center.longitude,
        'radius_m': radiusMeters.round(),
      },
      options: Options(receiveTimeout: const Duration(seconds: 40)),
    );

    final data = res.data?['data'];
    if (data is! Map || data['searched'] != true) {
      throw Exception('Pharmacy search is unavailable right now.');
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
