import 'dart:typed_data';

/// Network-level error types — adapter-agnostic.
///
/// Each [FluxAdapter] translates its own exceptions (e.g. [DioException],
/// [http.ClientException]) into this common enum so [FluxHttp.toMessage]
/// works identically regardless of the transport used.
enum FluxAdapterErrorType {
  connectionTimeout,
  sendTimeout,
  receiveTimeout,
  badCertificate,
  badResponse,
  cancelled,
  connectionError,
  unknown,
}

/// Exception thrown by [FluxAdapter] implementations on network-level failures,
/// i.e. before any HTTP response is received.
///
/// Adapters must catch their own errors and re-throw as [FluxAdapterException]
/// so [FluxHttp] can convert them into [FluxFailure] and [FluxMessage].
class FluxAdapterException implements Exception {
  const FluxAdapterException({
    required this.type,
    this.originalException,
  });

  final FluxAdapterErrorType type;
  final Object? originalException;

  @override
  String toString() =>
      'FluxAdapterException(type: $type, original: $originalException)';
}

// ─── File (adapter-agnostic) ──────────────────────────────────────────────────

/// An adapter-agnostic file descriptor for multipart uploads.
///
/// Pass a list of [FluxFile] to [FluxHttp.multipart]. Both [FluxDioAdapter]
/// and [FluxHttpAdapter] convert it internally to their own multipart format.
///
/// ```dart
/// import 'dart:typed_data';
///
/// final bytes = await File('photo.jpg').readAsBytes();
/// final file = FluxFile(
///   field: 'avatar',
///   bytes: bytes,
///   filename: 'photo.jpg',
///   contentType: 'image/jpeg',
/// );
/// ```
class FluxFile {
  const FluxFile({
    required this.field,
    required this.bytes,
    required this.filename,
    this.contentType,
  });

  /// Form field name (e.g. `'avatar'`).
  final String field;

  /// Raw file bytes.
  final Uint8List bytes;

  /// File name sent with the request (e.g. `'photo.jpg'`).
  final String filename;

  /// MIME type (e.g. `'image/jpeg'`). Inferred from [filename] by each adapter if `null`.
  final String? contentType;
}

// ─── Internal adapter contract types ─────────────────────────────────────────

/// A serialized HTTP request passed from [FluxHttp] to a [FluxAdapter].
class FluxAdapterRequest {
  const FluxAdapterRequest({
    required this.url,
    required this.method,
    required this.headers,
    this.body,
    this.queryParameters = const {},
    this.cancelToken,
  });

  final String url;

  /// HTTP verb in uppercase (e.g. `'GET'`, `'POST'`).
  final String method;
  final Map<String, String> headers;

  /// Already JSON-encoded body string, or `null` for bodyless requests.
  final String? body;
  final Map<String, dynamic> queryParameters;

  /// Adapter-specific cancellation token (e.g. Dio's [CancelToken]).
  /// Silently ignored by adapters that do not support cancellation.
  final Object? cancelToken;

  /// Returns a copy with the given fields replaced.
  FluxAdapterRequest copyWith({
    String? url,
    String? method,
    Map<String, String>? headers,
    String? body,
    Map<String, dynamic>? queryParameters,
    Object? cancelToken,
  }) =>
      FluxAdapterRequest(
        url: url ?? this.url,
        method: method ?? this.method,
        headers: headers ?? this.headers,
        body: body ?? this.body,
        queryParameters: queryParameters ?? this.queryParameters,
        cancelToken: cancelToken ?? this.cancelToken,
      );
}

/// A multipart upload request passed from [FluxHttp] to a [FluxAdapter].
class FluxAdapterMultipartRequest {
  const FluxAdapterMultipartRequest({
    required this.url,
    required this.method,
    required this.headers,
    this.fields = const {},
    this.files = const [],
    this.queryParameters = const {},
  });

  final String url;
  final String method;
  final Map<String, String> headers;
  final Map<String, String> fields;
  final List<FluxFile> files;
  final Map<String, dynamic> queryParameters;
}

/// Raw HTTP response returned by a [FluxAdapter].
class FluxAdapterResponse {
  const FluxAdapterResponse({
    required this.statusCode,
    required this.data,
  });

  final int statusCode;

  /// Decoded response body (already parsed JSON map/list, or raw [String]).
  final dynamic data;
}

// ─── FluxAdapter interface ────────────────────────────────────────────────────

/// Contract for HTTP transport adapters.
///
/// Implement this interface to plug in any HTTP client without changing
/// [FluxHttp] configuration.
///
/// Built-in implementations:
/// - [FluxDioAdapter] — backed by Dio (default, supports interceptors + cancel)
/// - [FluxHttpAdapter] — backed by `package:http` (lighter, no native deps)
///
/// **Custom adapter example:**
/// ```dart
/// class ChopperFluxAdapter implements FluxAdapter {
///   @override
///   Future<FluxAdapterResponse> send(FluxAdapterRequest req) async { ... }
///
///   @override
///   Future<FluxAdapterResponse> sendMultipart(FluxAdapterMultipartRequest req) async { ... }
/// }
/// ```
abstract interface class FluxAdapter {
  Future<FluxAdapterResponse> send(FluxAdapterRequest request);
  Future<FluxAdapterResponse> sendMultipart(FluxAdapterMultipartRequest request);
}
