import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'server_config.dart';

/// Secure-storage singleton (kept for onboarding flag caching).
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ),
);

/// Configured [Dio] instance with Supabase auth + refresh interceptors.
///
/// The access token is read from the active Supabase session on every request.
/// Supabase SDK handles token refresh automatically via its internal JWT logic;
/// this interceptor just attaches the current session token.
/// Marks a request that has already been retried after re-detecting the
/// server, so a genuinely down backend fails once instead of looping.
const String _rediscoveredKey = 'medintel_rediscovered';

/// Whether nothing answered at all, as opposed to a server that answered
/// with an error. Only the former is worth going to look for the server
/// over: a 500 means we found it just fine.
bool _isUnreachable(DioException e) {
  if (e.response != null) return false;
  return e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout;
}

final dioClientProvider = Provider<Dio>((ref) {
  // Watched, not read: changing the server address in settings rebuilds
  // this client, so the next request goes to the new host without a
  // restart.
  final baseUrl = ref.watch(serverConfigProvider);

  // Read, not watched: re-detecting the server changes the address, which
  // disposes this provider — so the error interceptor, which outlives that,
  // must not touch `ref`. The notifier itself survives the rebuild.
  final serverConfig = ref.read(serverConfigProvider.notifier);

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      contentType: 'application/json',
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Always use the live Supabase session token — the SDK refreshes it
        // transparently so this will always be a valid (or null) JWT.
        final session = Supabase.instance.client.auth.currentSession;
        final token = session?.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Nothing answered. Usually the backend moved with the network —
        // a new Wi-Fi, a new DHCP lease — and the stored address now points
        // at a host that isn't there. Re-detect and replay the request once,
        // so the feature recovers on its own instead of showing an error
        // until the app is restarted.
        if (_isUnreachable(error) &&
            error.requestOptions.extra[_rediscoveredKey] != true) {
          final req = error.requestOptions;
          req.extra[_rediscoveredKey] = true;
          if (await serverConfig.ensureReachable()) {
            req.baseUrl = serverConfig.baseUrl;
            try {
              return handler.resolve(await dio.fetch<dynamic>(req));
            } on DioException catch (retryFailure) {
              return handler.next(retryFailure);
            }
          }
          return handler.next(error);
        }

        if (error.response?.statusCode == 401) {
          // Attempt to refresh via Supabase SDK.
          try {
            final refreshed =
                await Supabase.instance.client.auth.refreshSession();
            final newToken = refreshed.session?.accessToken;
            if (newToken != null) {
              final req = error.requestOptions;
              req.headers['Authorization'] = 'Bearer $newToken';
              final clone = await dio.fetch<dynamic>(req);
              return handler.resolve(clone);
            }
          } catch (_) {
            // Refresh failed — fall through; the auth state change stream will
            // detect the signed-out state and the router will redirect.
          }
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});
