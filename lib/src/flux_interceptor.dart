import 'dart:async';

import 'flux_adapter.dart';

/// Adapter-agnostic hook executed before/after every [FluxHttp] request.
///
/// Extend this class and override only the methods you need.
///
/// ## Execution order
/// Interceptors run in list order for `onRequest`, and in **reverse** order
/// for `onResponse` / `onError` (similar to middleware stacks).
///
/// ## Custom example
/// ```dart
/// class LanguageInterceptor extends FluxInterceptor {
///   @override
///   FutureOr<FluxAdapterRequest> onRequest(FluxAdapterRequest request) {
///     return request.copyWith(
///       headers: {...request.headers, 'Accept-Language': 'es'},
///     );
///   }
/// }
/// ```
///
/// ## Built-in interceptors
/// - [FluxAuthInterceptor] — auto-attaches JWT and refreshes token on 401
/// - [FluxLogInterceptor]  — prints request/response in debug mode
abstract class FluxInterceptor {
  const FluxInterceptor();

  /// Called **before** the request is sent. Return a (possibly modified) request.
  ///
  /// Typical uses: inject auth token, add tracing headers, sign the request.
  FutureOr<FluxAdapterRequest> onRequest(FluxAdapterRequest request) => request;

  /// Called **after** a response arrives — any status code, including 4xx/5xx.
  ///
  /// [retry] lets you replay the request with a modified version without
  /// re-running the interceptor chain. Used by [FluxAuthInterceptor] to
  /// resend with a refreshed token after a 401.
  ///
  /// Typical uses: token refresh on 401, response normalisation, caching.
  FutureOr<FluxAdapterResponse> onResponse(
    FluxAdapterResponse response,
    FluxAdapterRequest originalRequest,
    Future<FluxAdapterResponse> Function(FluxAdapterRequest) retry,
  ) =>
      response;

  /// Called when the adapter throws a [FluxAdapterException] (network error —
  /// no HTTP response received).
  ///
  /// Return `null` to suppress the error and short-circuit to [FluxErr] with
  /// a 0 status (use with extreme caution — only for mocking/testing).
  /// Return the same or a modified [FluxAdapterException] to propagate it.
  ///
  /// Typical uses: logging, offline fallback, test stubbing.
  FutureOr<FluxAdapterException?> onError(FluxAdapterException error) => error;
}
