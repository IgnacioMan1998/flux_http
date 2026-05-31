import 'dart:io';

import 'package:dio/dio.dart';

import '../flux_adapter.dart';

/// [FluxAdapter] backed by [Dio].
///
/// **Default adapter** — used by [FluxHttp] when no adapter is specified.
///
/// Advantages over [FluxHttpAdapter]:
/// - Full interceptor chain (JWT refresh, logging, analytics, etc.)
/// - Cancel token support via Dio's [CancelToken]
/// - Multipart via Dio's [FormData] — no secondary HTTP client
/// - Certificate pinning, proxy support, transformer pipeline
///
/// ```dart
/// // Add interceptors before passing to FluxHttp:
/// final dio = Dio()
///   ..interceptors.addAll([
///     LogInterceptor(responseBody: true),
///     AuthInterceptor(tokenService),
///   ]);
///
/// final client = FluxHttp(
///   environment: 'prod',
///   baseUrls: {...},
///   adapter: FluxDioAdapter(dio: dio),
/// );
///
/// // Or access innerDio after construction:
/// (client.adapter as FluxDioAdapter).innerDio.interceptors.add(...);
/// ```
class FluxDioAdapter implements FluxAdapter {
  FluxDioAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Direct access to the underlying [Dio] instance.
  Dio get innerDio => _dio;

  @override
  Future<FluxAdapterResponse> send(FluxAdapterRequest req) async {
    try {
      final cancelToken = req.cancelToken is CancelToken
          ? req.cancelToken as CancelToken
          : null;

      final response = await _dio.request<dynamic>(
        req.url,
        data: req.body,
        queryParameters: req.queryParameters.isEmpty ? null : req.queryParameters,
        options: Options(method: req.method, headers: req.headers),
        cancelToken: cancelToken,
      );

      return FluxAdapterResponse(
        statusCode: response.statusCode ?? 0,
        data: response.data,
      );
    } on DioException catch (e) {
      // 4xx/5xx — Dio throws but a response exists; surface it as a status failure
      if (e.response != null) {
        return FluxAdapterResponse(
          statusCode: e.response!.statusCode ?? 0,
          data: e.response!.data,
        );
      }
      throw FluxAdapterException(
        type: _mapDioType(e.type, e.error),
        originalException: e,
      );
    } catch (e) {
      throw FluxAdapterException(
        type: FluxAdapterErrorType.unknown,
        originalException: e,
      );
    }
  }

  @override
  Future<FluxAdapterResponse> sendMultipart(FluxAdapterMultipartRequest req) async {
    try {
      final formData = FormData();

      for (final entry in req.fields.entries) {
        formData.fields.add(MapEntry(entry.key, entry.value));
      }
      for (final file in req.files) {
        formData.files.add(MapEntry(
          file.field,
          MultipartFile.fromBytes(
            file.bytes,
            filename: file.filename,
            // contentType: Dio infers from filename extension automatically
          ),
        ));
      }

      var url = req.url;
      if (req.queryParameters.isNotEmpty) {
        final uri = Uri.parse(url).replace(
          queryParameters: req.queryParameters.map((k, v) => MapEntry(k, '$v')),
        );
        url = uri.toString();
      }

      final response = await _dio.request<dynamic>(
        url,
        data: formData,
        options: Options(method: req.method, headers: req.headers),
      );

      return FluxAdapterResponse(
        statusCode: response.statusCode ?? 0,
        data: response.data,
      );
    } on DioException catch (e) {
      if (e.response != null) {
        return FluxAdapterResponse(
          statusCode: e.response!.statusCode ?? 0,
          data: e.response!.data,
        );
      }
      throw FluxAdapterException(
        type: _mapDioType(e.type, e.error),
        originalException: e,
      );
    } catch (e) {
      throw FluxAdapterException(
        type: FluxAdapterErrorType.unknown,
        originalException: e,
      );
    }
  }

  FluxAdapterErrorType _mapDioType(DioExceptionType type, Object? error) {
    return switch (type) {
      DioExceptionType.connectionTimeout => FluxAdapterErrorType.connectionTimeout,
      DioExceptionType.sendTimeout => FluxAdapterErrorType.sendTimeout,
      DioExceptionType.receiveTimeout => FluxAdapterErrorType.receiveTimeout,
      DioExceptionType.badCertificate => FluxAdapterErrorType.badCertificate,
      DioExceptionType.badResponse => FluxAdapterErrorType.badResponse,
      DioExceptionType.cancel => FluxAdapterErrorType.cancelled,
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        error is SocketException
            ? FluxAdapterErrorType.connectionError
            : FluxAdapterErrorType.unknown,
    };
  }
}
