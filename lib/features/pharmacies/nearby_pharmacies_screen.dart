import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_names.dart';
import 'pharmacy_service.dart';
import '../../core/theme/app_colors.dart';

/// Live "Nearby Pharmacies" — real device location + real pharmacies from
/// OpenStreetMap, rendered on an interactive map. No API key required.
class NearbyPharmaciesScreen extends ConsumerWidget {
  const NearbyPharmaciesScreen({super.key});

  static const _ink = AppColors.textPrimary;
  static const _muted = AppColors.textSecondary;
  static const _primary = AppColors.info;
  static const _green = AppColors.successDeep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nearbyPharmaciesProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        title: const Text('Nearby Pharmacies'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(nearbyPharmaciesProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Finding pharmacies near you…',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_off, size: 48, color: _muted),
                const SizedBox(height: 12),
                const Text(
                  'Could not load nearby pharmacies',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(nearbyPharmaciesProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (result) => _content(context, ref, result),
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, NearbyResult result) {
    final center = result.center;
    final pharmacies = result.pharmacies;

    return Column(
      children: [
        SizedBox(
          height: 280,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.medintel.nexus',
              ),
              MarkerLayer(
                markers: [
                  // User location
                  Marker(
                    point: center,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Color(0x55000000), blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                  // Pharmacies
                  for (final p in pharmacies)
                    Marker(
                      point: p.location,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.local_pharmacy,
                        color: _green,
                        size: 30,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: AppColors.neutral50,
          child: Text(
            pharmacies.isEmpty
                ? 'No pharmacies found within 3 km'
                : '${pharmacies.length} pharmacies within 3 km',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        Expanded(
          child: pharmacies.isEmpty
              ? const Center(
                  child: Text(
                    'Try moving the map or refreshing.',
                    style: TextStyle(color: _muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: pharmacies.length,
                  separatorBuilder: (_, __) => const Divider(height: 18),
                  itemBuilder: (_, i) => _row(pharmacies[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(Pharmacy p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.tintGreen,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.local_pharmacy, color: _green, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              if ((p.address ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  p.address!,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x142563EB),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            p.distanceLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
          ),
        ),
      ],
    );
  }
}
