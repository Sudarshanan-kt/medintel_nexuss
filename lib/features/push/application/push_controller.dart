import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/push_service.dart';
import '../data/push_token_repository.dart';

/// Registers this device for push notifications whenever the user is
/// authenticated, and keeps the registration current across token
/// refreshes. Watch this provider once from a long-lived widget (the app
/// shell) to keep it alive — same pattern as
/// AppShell watching remindersControllerProvider.
class PushController extends Notifier<void> {
  StreamSubscription<String>? _refreshSub;

  @override
  void build() {
    ref.onDispose(() => _refreshSub?.cancel());

    ref.listen(authStatusProvider, (previous, next) {
      if (next == AuthStatus.authenticated) unawaited(_register());
    });

    if (ref.read(authStatusProvider) == AuthStatus.authenticated) {
      unawaited(_register());
    }
  }

  Future<void> _register() async {
    final service = ref.read(pushServiceProvider);
    final token = await service.requestPermissionAndGetToken();
    if (token != null) await _save(token);

    service.listenForegroundMessages();

    unawaited(_refreshSub?.cancel());
    _refreshSub = service.onTokenRefresh.listen(_save);
  }

  Future<void> _save(String token) async {
    final userId = ref.read(authControllerProvider).valueOrNull?.user?.id;
    if (userId == null) return;
    try {
      await ref.read(pushTokenRepositoryProvider).registerToken(
            userId: userId,
            fcmToken: token,
            platform: kIsWeb ? 'web' : 'android',
          );
    } catch (_) {
      // Table may not exist yet locally / offline — push registration is
      // best-effort, never blocks the rest of the app.
    }
  }
}

final pushControllerProvider = NotifierProvider<PushController, void>(
  PushController.new,
);
