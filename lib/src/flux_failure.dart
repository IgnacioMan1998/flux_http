import 'flux_adapter.dart';

/// Represents a failed HTTP request.
///
/// Either:
/// - A network-level failure (no HTTP response) — [errorType] is set, [statusCode] is null.
/// - An HTTP error response — [statusCode] is set (4xx/5xx), [errorType] is null.
///
/// When produced via [FluxApiBase.resolveFailure], [resolvedMessage] is
/// pre-populated with a human-readable string — no need to call
/// `client.toMessage(failure)` at every call site.
class FluxFailure {
  const FluxFailure({
    this.statusCode,
    this.exception,
    this.data,
    this.errorType,
    this.resolvedMessage,
  });

  /// HTTP status code returned by the server (4xx/5xx), if any.
  final int? statusCode;

  /// The original low-level exception (e.g. [SocketException]).
  final Object? exception;

  /// Raw response body from the server, if any.
  final Object? data;

  /// Set when the failure is a network-level error (no HTTP response received).
  /// `null` means the server responded with a non-2xx status code.
  final FluxAdapterErrorType? errorType;

  /// Human-readable message, stamped by [FluxApiBase.resolveFailure].
  ///
  /// `null` when the failure was not processed through [FluxApiBase] — call
  /// `client.toMessage(this)` in that case.
  final String? resolvedMessage;

  /// Returns `true` when the failure occurred before any HTTP response arrived.
  bool get isNetworkError => errorType != null;

  FluxFailure copyWith({
    int? statusCode,
    Object? exception,
    Object? data,
    FluxAdapterErrorType? errorType,
    String? resolvedMessage,
  }) =>
      FluxFailure(
        statusCode: statusCode ?? this.statusCode,
        exception: exception ?? this.exception,
        data: data ?? this.data,
        errorType: errorType ?? this.errorType,
        resolvedMessage: resolvedMessage ?? this.resolvedMessage,
      );

  @override
  String toString() =>
      'FluxFailure(statusCode: $statusCode, errorType: $errorType, data: $data)';
}
