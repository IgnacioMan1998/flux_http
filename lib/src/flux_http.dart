import 'dart:convert';

import 'adapters/flux_dio_adapter.dart';
import 'flux_adapter.dart';
import 'flux_error_messages.dart';
import 'flux_failure.dart';
import 'flux_interceptor.dart';
import 'flux_message.dart';
import 'flux_method.dart';

/// A configurable, multi-environment, multi-backend HTTP client.
///
/// Transport is pluggable via [FluxAdapter]:
/// - [FluxDioAdapter] (default) — Dio: cancel tokens, certificate pinning
/// - [FluxHttpAdapter] — lighter `package:http` backend
/// - Custom — implement [FluxAdapter] for any HTTP client
///
/// Middleware is pluggable via [FluxInterceptor]:
/// - [FluxAuthInterceptor] — auto-attaches JWT and refreshes token on 401
/// - [FluxLogInterceptor]  — prints request/response details
/// - Custom — extend [FluxInterceptor] and override any hooks
///
/// Returns [FluxResult] (sealed [FluxOk]/[FluxErr]) — no external FP library required.
///
/// ## Quick start
/// ```dart
/// final client = FluxHttp(
///   environment: 'prod',
///   baseUrls: {
///     'dev':  {'main': 'https://dev.api.myapp.com/api/'},
///     'prod': {'main': 'https://api.myapp.com/api/'},
///   },
///   defaultHeaders: {'Client-Id': 'my-app'},
///   errorMessages: FluxErrorMessages.spanish,
///   interceptors: [
///     FluxAuthInterceptor(
///       getToken: () => storage.read('token'),
///       refreshToken: () => authApi.refresh(),
///       onRefreshFailed: () => router.go('/login'),
///     ),
///     if (kDebugMode) const FluxLogInterceptor(),
///   ],
/// );
///
/// final result = await client.request<UserModel>(
///   '/users/me',
///   onSuccess: UserModel.fromJson,
/// );
///
/// result.fold(
///   (failure) => showError(client.toMessage(failure).message),
///   (user)    => setState(() => _user = user),
/// );
/// ```
class FluxHttp {
  FluxHttp({
    required this.environment,
    required this.baseUrls,
    this.defaultHeaders = const {'Content-Type': 'application/json'},
    this.errorMessages = const FluxErrorMessages(),
    this.interceptors = const [],
    FluxAdapter? adapter,
  }) : _adapter = adapter ?? FluxDioAdapter();

  /// Active environment key — must match a top-level key in [baseUrls].
  final String environment;

  /// Base URLs indexed by environment → backend name.
  ///
  /// ```dart
  /// {
  ///   'dev':  {'main': 'https://dev.api.com/', 'cdn': 'https://cdn.dev.com/'},
  ///   'prod': {'main': 'https://api.com/',     'cdn': 'https://cdn.com/'},
  /// }
  /// ```
  final Map<String, Map<String, String>> baseUrls;

  /// Headers merged into every request. Override per-request via the [headers] param.
  final Map<String, String> defaultHeaders;

  /// Human-readable error messages for [toMessage]. Defaults to English.
  /// Use [FluxErrorMessages.spanish] or supply your own instance.
  final FluxErrorMessages errorMessages;

  /// Middleware executed around every request/response cycle.
  ///
  /// Interceptors run in list order for [FluxInterceptor.onRequest] and in
  /// **reverse** order for [FluxInterceptor.onResponse] / [FluxInterceptor.onError].
  ///
  /// ```dart
  /// interceptors: [
  ///   FluxAuthInterceptor(...),   // onRequest: first,  onResponse: last
  ///   const FluxLogInterceptor(), // onRequest: second, onResponse: first
  /// ]
  /// ```
  final List<FluxInterceptor> interceptors;

  final FluxAdapter _adapter;

  /// Access the underlying [FluxAdapter].
  ///
  /// ```dart
  /// // Access the inner Dio instance (FluxDioAdapter):
  /// (client.adapter as FluxDioAdapter).innerDio;
  ///
  /// // Access the inner http.Client (FluxHttpAdapter):
  /// (client.adapter as FluxHttpAdapter).innerClient;
  /// ```
  FluxAdapter get adapter => _adapter;

  // ---------------------------------------------------------------------------
  // request<R>
  // ---------------------------------------------------------------------------

  /// Executes an HTTP request and returns a [FluxResult].
  ///
  /// - [path]: relative path or full URL (full URL ignores [backend]).
  /// - [method]: HTTP verb. Defaults to [FluxMethod.get].
  /// - [backend]: key in `baseUrls[environment]` to select the base URL.
  /// - [headers]: merged on top of [defaultHeaders] for this request only.
  /// - [queryParameters]: appended as query string.
  /// - [body]: request body serialized to JSON automatically.
  /// - [cancelToken]: Dio [CancelToken] when using [FluxDioAdapter]; ignored otherwise.
  /// - [onSuccess]: maps the decoded response body to [R].
  Future<FluxResult<R>> request<R>(
    String path, {
    FluxMethod method = FluxMethod.get,
    String backend = 'main',
    Map<String, String> headers = const {},
    Map<String, dynamic> queryParameters = const {},
    Map<String, dynamic> body = const {},
    Object? cancelToken,
    required R Function(dynamic responseBody) onSuccess,
  }) async {
    try {
      final url = _resolveUrl(path, backend);
      final mergedHeaders = {...defaultHeaders, ...headers};

      // ── Build initial request ──────────────────────────────────────────────
      var adapterRequest = FluxAdapterRequest(
        url: url,
        method: method.name.toUpperCase(),
        headers: mergedHeaders,
        body: body.isEmpty ? null : jsonEncode(body),
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );

      // ── onRequest interceptors (in order) ─────────────────────────────────
      for (final interceptor in interceptors) {
        adapterRequest = await interceptor.onRequest(adapterRequest);
      }

      // ── Send ──────────────────────────────────────────────────────────────
      FluxAdapterResponse response;
      try {
        response = await _adapter.send(adapterRequest);
      } on FluxAdapterException catch (e) {
        // onError interceptors (in reverse order)
        FluxAdapterException? current = e;
        for (final interceptor in interceptors.reversed) {
          current = await interceptor.onError(current!);
          if (current == null) break;
        }
        if (current != null) {
          return FluxErr(
              FluxFailure(errorType: current.type, exception: current.originalException));
        }
        // Error suppressed by an interceptor — surface as unknown failure
        return FluxErr(FluxFailure(statusCode: 0, data: 'Error suppressed by interceptor'));
      }

      // ── onResponse interceptors (in reverse order) ────────────────────────
      // `retry` gives interceptors a way to replay the raw request (e.g. after
      // token refresh) without re-running the interceptor chain.
      for (final interceptor in interceptors.reversed) {
        response = await interceptor.onResponse(
          response,
          adapterRequest,
          _adapter.send, // raw retry — bypasses interceptors to prevent loops
        );
      }

      // ── Result ────────────────────────────────────────────────────────────
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return FluxOk(onSuccess(response.data));
      }
      return FluxErr(FluxFailure(statusCode: response.statusCode, data: response.data));
    } on FluxAdapterException catch (e) {
      return FluxErr(FluxFailure(errorType: e.type, exception: e.originalException));
    } catch (e) {
      return FluxErr(FluxFailure(statusCode: 0, data: '$e', exception: e));
    }
  }

  // ---------------------------------------------------------------------------
  // multipart<R>
  // ---------------------------------------------------------------------------

  /// Sends a multipart/form-data request (file uploads).
  ///
  /// Interceptors run the same way as [request] — [onRequest] fires before
  /// the upload, [onResponse] fires after (including 401 refresh support).
  ///
  /// Works with **any** adapter:
  /// - [FluxDioAdapter]: uses Dio's [FormData] natively.
  /// - [FluxHttpAdapter]: uses `http.MultipartRequest`.
  ///
  /// ```dart
  /// final bytes = await File('photo.jpg').readAsBytes();
  ///
  /// final result = await client.multipart<ProfileModel>(
  ///   '/users/me/avatar',
  ///   fields: {'userId': '42'},
  ///   files: [
  ///     FluxFile(
  ///       field: 'avatar',
  ///       bytes: bytes,
  ///       filename: 'photo.jpg',
  ///       contentType: 'image/jpeg',
  ///     ),
  ///   ],
  ///   onSuccess: ProfileModel.fromJson,
  /// );
  /// ```
  Future<FluxResult<R>> multipart<R>(
    String path, {
    FluxMethod method = FluxMethod.post,
    String backend = 'main',
    Map<String, String> headers = const {},
    Map<String, String> fields = const {},
    List<FluxFile> files = const [],
    Map<String, dynamic> queryParameters = const {},
    required R Function(dynamic responseBody) onSuccess,
  }) async {
    try {
      final url = _resolveUrl(path, backend);
      // Remove Content-Type: each adapter sets the correct multipart boundary
      final mergedHeaders = {...defaultHeaders, ...headers}
        ..remove('Content-Type')
        ..remove('content-type');

      // ── Build a synthetic FluxAdapterRequest for interceptor onRequest ────
      // Multipart bodies can't be JSON-encoded, so body is left null here.
      // Headers (e.g. Authorization) are still injected by interceptors.
      var interceptorRequest = FluxAdapterRequest(
        url: url,
        method: method.name.toUpperCase(),
        headers: mergedHeaders,
        queryParameters: queryParameters,
      );

      // ── onRequest interceptors (in order) ─────────────────────────────────
      for (final interceptor in interceptors) {
        interceptorRequest = await interceptor.onRequest(interceptorRequest);
      }

      // ── Send ──────────────────────────────────────────────────────────────
      FluxAdapterResponse response;
      try {
        response = await _adapter.sendMultipart(FluxAdapterMultipartRequest(
          url: interceptorRequest.url,
          method: interceptorRequest.method,
          headers: interceptorRequest.headers,
          fields: fields,
          files: files,
          queryParameters: interceptorRequest.queryParameters,
        ));
      } on FluxAdapterException catch (e) {
        FluxAdapterException? current = e;
        for (final interceptor in interceptors.reversed) {
          current = await interceptor.onError(current!);
          if (current == null) break;
        }
        if (current != null) {
          return FluxErr(
              FluxFailure(errorType: current.type, exception: current.originalException));
        }
        return FluxErr(FluxFailure(statusCode: 0, data: 'Error suppressed by interceptor'));
      }

      // ── onResponse interceptors ───────────────────────────────────────────
      // Retry for multipart: rebuild the full multipart request with updated headers.
      for (final interceptor in interceptors.reversed) {
        response = await interceptor.onResponse(
          response,
          interceptorRequest,
          (retryRequest) => _adapter.sendMultipart(FluxAdapterMultipartRequest(
            url: retryRequest.url,
            method: retryRequest.method,
            headers: retryRequest.headers,
            fields: fields,
            files: files,
            queryParameters: retryRequest.queryParameters,
          )),
        );
      }

      // ── Result ────────────────────────────────────────────────────────────
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return FluxOk(onSuccess(response.data));
      }
      return FluxErr(FluxFailure(statusCode: response.statusCode, data: response.data));
    } on FluxAdapterException catch (e) {
      return FluxErr(FluxFailure(errorType: e.type, exception: e.originalException));
    } catch (e) {
      return FluxErr(FluxFailure(statusCode: 0, data: '$e', exception: e));
    }
  }

  // ---------------------------------------------------------------------------
  // toMessage
  // ---------------------------------------------------------------------------

  /// Converts a [FluxFailure] into a human-readable [FluxMessage].
  ///
  /// Works identically regardless of which [FluxAdapter] is in use.
  ///
  /// ```dart
  /// result.fold(
  ///   (failure) => showSnackbar(client.toMessage(failure).message),
  ///   (value)   => ...,
  /// );
  /// ```
  FluxMessage toMessage(FluxFailure failure) {
    if (failure.errorType != null) {
      final message = switch (failure.errorType!) {
        FluxAdapterErrorType.connectionTimeout ||
        FluxAdapterErrorType.sendTimeout ||
        FluxAdapterErrorType.receiveTimeout =>
          errorMessages.timeout,
        FluxAdapterErrorType.badCertificate => errorMessages.badCertificate,
        FluxAdapterErrorType.badResponse => errorMessages.badResponse,
        FluxAdapterErrorType.cancelled => errorMessages.cancelled,
        FluxAdapterErrorType.connectionError => errorMessages.network,
        FluxAdapterErrorType.unknown => errorMessages.unknown,
      };
      return FluxMessage(code: '0', message: message);
    }

    final code = failure.statusCode;
    if (code != null) {
      final message = switch (code) {
        400 => errorMessages.badResponse,
        401 => errorMessages.unauthorized,
        403 => errorMessages.forbidden,
        404 => errorMessages.notFound,
        405 => errorMessages.methodNotAllowed,
        503 => errorMessages.serviceUnavailable,
        >= 500 && < 600 => errorMessages.serverError,
        _ => errorMessages.unknown,
      };
      return FluxMessage(code: '$code', message: message);
    }

    return FluxMessage(code: '0', message: errorMessages.unknown);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  String _resolveUrl(String path, String backend) {
    if (path.startsWith('http')) return path;
    final envUrls = baseUrls[environment];
    assert(envUrls != null,
        '[FluxHttp] No URLs configured for environment "$environment".');
    final base = envUrls![backend];
    assert(base != null,
        '[FluxHttp] No base URL for backend "$backend" in environment "$environment".');
    return '$base$path';
  }
}

// ─── FluxResult — sealed union ────────────────────────────────────────────────

/// Sealed result type returned by [FluxHttp.request] and [FluxHttp.multipart].
///
/// **Pattern matching (Dart 3):**
/// ```dart
/// switch (result) {
///   case FluxOk(:final value):    print(value);
///   case FluxErr(:final failure): print(client.toMessage(failure).message);
/// }
/// ```
/// **Functional fold (like dartz Either):**
/// ```dart
/// result.fold(
///   (failure) => state = state.copyWith(error: client.toMessage(failure).message),
///   (value)   => state = state.copyWith(data: value),
/// );
/// ```
sealed class FluxResult<T> {
  const FluxResult();

  /// Functional fold — runs [onSuccess] on [FluxOk], [onFailure] on [FluxErr].
  R fold<R>(
    R Function(FluxFailure failure) onFailure,
    R Function(T value) onSuccess,
  ) {
    return switch (this) {
      FluxOk(:final value) => onSuccess(value),
      FluxErr(:final failure) => onFailure(failure),
    };
  }

  /// Returns the value if [FluxOk], otherwise `null`.
  T? get valueOrNull => switch (this) {
        FluxOk(:final value) => value,
        FluxErr() => null,
      };

  /// Returns the failure if [FluxErr], otherwise `null`.
  FluxFailure? get failureOrNull => switch (this) {
        FluxOk() => null,
        FluxErr(:final failure) => failure,
      };

  bool get isOk => this is FluxOk<T>;
  bool get isErr => this is FluxErr<T>;

  /// Transforms the success value with [transform], leaving [FluxErr] unchanged.
  ///
  /// Useful in repository layers to map a data model to a domain entity without
  /// unwrapping the result:
  ///
  /// ```dart
  /// // In RepositoryImpl:
  /// final result = await api.fetchUser(id);
  /// return result.map((model) => model.toEntity());
  /// ```
  FluxResult<R> map<R>(R Function(T value) transform) => switch (this) {
        FluxOk(:final value) => FluxOk(transform(value)),
        FluxErr(:final failure) => FluxErr(failure),
      };

  /// Fold variant that resolves [FluxFailure] to a [FluxMessage] before
  /// calling [onFailure] — eliminates `client.toMessage(failure)` boilerplate.
  ///
  /// If [FluxApiBase.resolveFailure] was already called on this result, the
  /// pre-resolved message is reused and [client] is not queried again.
  ///
  /// ```dart
  /// result.foldMessage(
  ///   client,
  ///   (msg) => state = state.copyWith(error: msg.message),
  ///   (value) => state = state.copyWith(data: value),
  /// );
  /// ```
  R foldMessage<R>(
    FluxHttp client,
    R Function(FluxMessage message) onFailure,
    R Function(T value) onSuccess,
  ) =>
      fold(
        (failure) {
          final msg = failure.resolvedMessage != null
              ? FluxMessage(
                  code: '${failure.statusCode ?? 0}',
                  message: failure.resolvedMessage!)
              : client.toMessage(failure);
          return onFailure(msg);
        },
        onSuccess,
      );
}

/// Success variant of [FluxResult].
final class FluxOk<T> extends FluxResult<T> {
  const FluxOk(this.value);
  final T value;
}

/// Failure variant of [FluxResult].
final class FluxErr<T> extends FluxResult<T> {
  const FluxErr(this.failure);
  final FluxFailure failure;
}
