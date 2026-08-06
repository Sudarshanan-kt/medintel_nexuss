import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/health_connect_service.dart';

class WearablesState {
  const WearablesState({
    this.connected = false,
    this.loading = false,
    this.snapshot = WearableSnapshot.empty,
  });

  final bool connected;
  final bool loading;
  final WearableSnapshot snapshot;

  WearablesState copyWith({bool? connected, bool? loading, WearableSnapshot? snapshot}) {
    return WearablesState(
      connected: connected ?? this.connected,
      loading: loading ?? this.loading,
      snapshot: snapshot ?? this.snapshot,
    );
  }
}

/// Manages the Health Connect / HealthKit connection state and the latest
/// fetched snapshot. Nothing here is scheduled/background — the user
/// explicitly connects from the Health Risk Insights screen, matching the
/// "opt-in, never silent" posture the rest of the app already uses for
/// biometrics and notifications.
class WearablesController extends Notifier<WearablesState> {
  HealthConnectService get _service => ref.read(healthConnectServiceProvider);

  @override
  WearablesState build() => const WearablesState();

  Future<void> connect() async {
    state = state.copyWith(loading: true);
    final granted = await _service.requestPermissions();
    if (!granted) {
      state = state.copyWith(loading: false, connected: false);
      return;
    }
    final snapshot = await _service.fetchTodaySnapshot();
    state = WearablesState(connected: true, loading: false, snapshot: snapshot);
  }

  Future<void> refresh() async {
    if (!state.connected) return;
    state = state.copyWith(loading: true);
    final snapshot = await _service.fetchTodaySnapshot();
    state = state.copyWith(loading: false, snapshot: snapshot);
  }
}

final wearablesControllerProvider =
    NotifierProvider<WearablesController, WearablesState>(
  WearablesController.new,
);
