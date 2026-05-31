import 'dart:async';

import '../flux_adapter.dart';
import '../flux_interceptor.dart';

/// Interceptor that prints request and response details.
///
/// Enable only in debug builds to avoid leaking sensitive headers/bodies in
/// production logs:
///
/// ```dart
/// import 'package:flutter/foundation.dart' show kDebugMode;
///
/// final client = FluxHttp(
///   environment: 'prod',
///   baseUrls: {...},
///   interceptors: [
///     if (kDebugMode) const FluxLogInterceptor(),
///   ],
/// );
/// ```
///
/// To pipe output to a custom sink (e.g. a crash reporter):
///
/// ```dart
/// FluxLogInterceptor(
///   logger: (msg) => FirebaseCrashlytics.instance.log(msg),
/// )
/// ```
class FluxLogInterceptor extends FluxInterceptor {
  const FluxLogInterceptor({
    this.logRequest = true,
    this.logResponse = true,
    this.logErrors = true,
    this.logRequestBody = false,
    this.logger,
  });

  /// Whether to print outgoing requests. Defaults to `true`.
  final bool logRequest;

  /// Whether to print incoming responses. Defaults to `true`.
  final bool logResponse;

  /// Whether to print network-level errors. Defaults to `true`.
  final bool logErrors;

  /// Whether to include the serialized request body. Defaults to `false`
  /// (avoid leaking sensitive data in shared logs).
  final bool logRequestBody;

  /// Custom output sink. Defaults to `print`.
  final void Function(String message)? logger;

  void _log(String message) => (logger ?? _defaultPrint)(message);

  // ignore: avoid_print
  static void _defaultPrint(String msg) => print(msg);

  @override
  FutureOr<FluxAdapterRequest> onRequest(FluxAdapterRequest request) {
    if (!logRequest) return request;

    final buffer = StringBuffer()
      ..writeln('[FluxHttp] --> ${request.method} ${request.url}');

    if (request.queryParameters.isNotEmpty) {
      buffer.writeln('  query:   ${request.queryParameters}');
    }
    if (request.headers.isNotEmpty) {
      buffer.writeln('  headers: ${request.headers}');
    }
    if (logRequestBody && request.body != null) {
      buffer.writeln('  body:    ${request.body}');
    }

    _log(buffer.toString().trimRight());
    return request;
  }

  @override
  FutureOr<FluxAdapterResponse> onResponse(
    FluxAdapterResponse response,
    FluxAdapterRequest originalRequest,
    Future<FluxAdapterResponse> Function(FluxAdapterRequest) retry,
  ) {
    if (!logResponse) return response;
    _log('[FluxHttp] <-- ${response.statusCode} ${originalRequest.url}');
    return response;
  }

  @override
  FutureOr<FluxAdapterException?> onError(FluxAdapterException error) {
    if (!logErrors) return error;
    _log('[FluxHttp] ✗ ${error.type} — ${error.originalException}');
    return error;
  }
}
