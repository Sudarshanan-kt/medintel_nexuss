import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_endpoints.dart';

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
final dioClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
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
