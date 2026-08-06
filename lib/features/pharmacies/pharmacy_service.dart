import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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

/// Finds real pharmacies around the user using only free services:
///   • Browser/device geolocation (no key)
///   • OpenStreetMap Overpass API (no key) filtered to amenity=pharmacy
class PharmacyService {
  PharmacyService(this._dio);
  final Dio _dio;

  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

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
  Future<NearbyResult> findNearby({double radiusMeters = 3000}) async {
    final center = await _resolveLocation();
    final lat = center.latitude;
    final lon = center.longitude;

    final query = '''
[out:json][timeout:25];
(
  node["amenity"="pharmacy"](around:$radiusMeters,$lat,$lon);
  way["amenity"="pharmacy"](around:$radiusMeters,$lat,$lon);
  node["healthcare"="pharmacy"](around:$radiusMeters,$lat,$lon);
);
out center 60;
''';

    Object? lastError;
    for (final url in _overpassEndpoints) {
      try {
        final res = await _dio.post<String>(
          url,
          data: 'data=${Uri.encodeComponent(query)}',
          options: Options(
            contentType: 'application/x-www-form-urlencoded',
            responseType: ResponseType.plain,
          ),
        );
        final pharmacies = _parse(res.data, center);
        return NearbyResult(center: center, pharmacies: pharmacies);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Could not load pharmacies: $lastError');
  }

  List<Pharmacy> _parse(String? body, LatLng center) {
    if (body == null || body.isEmpty) return [];
    final doc = jsonDecode(body) as Map<String, dynamic>;
    final elements = (doc['elements'] as List? ?? const []);
    final list = <Pharmacy>[];

    for (final raw in elements) {
      final e = (raw as Map).cast<String, dynamic>();
      double? lat = (e['lat'] as num?)?.toDouble();
      double? lon = (e['lon'] as num?)?.toDouble();
      final center0 = (e['center'] as Map?)?.cast<String, dynamic>();
      lat ??= (center0?['lat'] as num?)?.toDouble();
      lon ??= (center0?['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};
      final name = (tags['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue; // medical shops only, named

      final loc = LatLng(lat, lon);
      list.add(
        Pharmacy(
          name: name,
          location: loc,
          address: _addressOf(tags),
          distanceMeters: _haversine(center, loc),
        ),
      );
    }

    list.sort(
      (a, b) => (a.distanceMeters ?? 1e12).compareTo(b.distanceMeters ?? 1e12),
    );
    return list;
  }

  String? _addressOf(Map<String, dynamic> t) {
    final parts = [
      t['addr:housenumber'],
      t['addr:street'],
      t['addr:suburb'] ?? t['addr:neighbourhood'],
      t['addr:city'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Great-circle distance in metres.
  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _rad(double deg) => deg * math.pi / 180.0;
}

final pharmacyServiceProvider = Provider<PharmacyService>((ref) {
  // Standalone Dio so map/Overpass calls don't inherit the API auth headers.
  return PharmacyService(Dio());
});

/// Loads nearby pharmacies once per screen visit.
final nearbyPharmaciesProvider = FutureProvider<NearbyResult>((ref) async {
  return ref.read(pharmacyServiceProvider).findNearby();
});
