import 'dart:async';

import '../flux_adapter.dart';
import '../flux_interceptor.dart';

/// Interceptor that auto-attaches a JWT to every request and silently
/// refreshes the token when the server returns 401.
///
/// ## Setup
/// ```dart
/// final client = FluxHttp(
///   environment: 'prod',
///   baseUrls: {...},
///   interceptors: [
///     FluxAuthInterceptor(
///       getToken: () => secureStorage.read('access_token'),
///       refreshToken: () async {
///         final result = await authApi.refresh();
///         return result.fold((_) => null, (tokens) {
///           secureStorage.write('access_token', tokens.access);
///           return tokens.access;
///         });
///       },
///       onRefreshFailed: () {
///         secureStorage.deleteAll();
///         router.go('/login');
///       },
///     ),
///   ],
/// );
/// ```
///
/// ## Flow
/// 1. [onRequest] — reads [getToken] and injects `Authorization: Bearer <token>`.
/// 2. [onResponse] — if the server returns 401:
///    a. Calls [refreshToken] once.
///    b. If a new token is returned, retries the original request with it.
///    c. If [refreshToken] returns `null`, calls [onRefreshFailed] and surfaces
///       the 401 as a [FluxErr] to the caller.
class FluxAuthInterceptor extends FluxInterceptor {
  FluxAuthInterceptor({
    required this.getToken,
    required this.refreshToken,
    this.onRefreshFailed,
    this.tokenHeader = 'Authorization',
    this.tokenPrefix = 'Bearer',
  });

  /// Returns the current access token, or `null` if the user is not signed in.
  /// Called before every request — keep it fast (read from memory / secure storage).
  final Future<String?> Function() getToken;

  /// Called on 401. Should silently obtain a new access token and return it,
  /// or return `null` if the session can no longer be renewed.
  final Future<String?> Function() refreshToken;

  /// Called when [refreshToken] returns `null` (session expired / invalid).
  /// Use to navigate to the login screen, clear credentials, etc.
  final void Function()? onRefreshFailed;

  /// Header name. Defaults to `'Authorization'`.
  final String tokenHeader;

  /// Token prefix. Defaults to `'Bearer'`.
  final String tokenPrefix;

  // Guards against concurrent refresh attempts (e.g. two parallel 401s).
  bool _isRefreshing = false;

  @override
  Future<FluxAdapterRequest> onRequest(FluxAdapterRequest request) async {
    final token = await getToken();
    if (token == null) return request;
    return request.copyWith(
      headers: {...request.headers, tokenHeader: '$tokenPrefix $token'},
    );
  }

  @override
  Future<FluxAdapterResponse> onResponse(
    FluxAdapterResponse response,
    FluxAdapterRequest originalRequest,
    Future<FluxAdapterResponse> Function(FluxAdapterRequest) retry,
  ) async {
    // Not a 401, or a refresh loop is already in progress — pass through.
    if (response.statusCode != 401 || _isRefreshing) return response;

    _isRefreshing = true;
    try {
      final newToken = await refreshToken();

      if (newToken == null) {
        // Refresh failed — notify caller and surface the 401.
        onRefreshFailed?.call();
        return response;
      }

      // Retry the original request with the fresh token.
      // `retry` bypasses the interceptor chain, preventing an infinite loop.
      return retry(
        originalRequest.copyWith(
          headers: {
            ...originalRequest.headers,
            tokenHeader: '$tokenPrefix $newToken',
          },
        ),
      );
    } finally {
      _isRefreshing = false;
    }
  }
}
