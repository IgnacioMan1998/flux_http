import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../flux_adapter.dart';

/// [FluxAdapter] backed by `package:http`.
///
/// Use this when:
/// - You prefer a lighter dependency without Dio
/// - You need to run on platforms or environments where Dio is unavailable
/// - You already have an [http.Client] instance (e.g. from `package:http_mock_adapter` in tests)
///
/// Limitations vs [FluxDioAdapter]:
/// - No Dio interceptor chain (use `http.BaseClient` subclassing instead)
/// - Cancel tokens are silently ignored
/// - No built-in request transformer pipeline
///
/// ```dart
/// final client = FluxHttp(
///   environment: 'prod',
///   baseUrls: {...},
///   adapter: FluxHttpAdapter(),
/// );
///
/// // With a custom http.Client (e.g. for testing):
/// final client = FluxHttp(
///   environment: 'test',
///   baseUrls: {...},
///   adapter: FluxHttpAdapter(client: MockClient(...)),
/// );
/// ```
class FluxHttpAdapter implements FluxAdapter {
  FluxHttpAdapter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Direct access to the underlying [http.Client] instance.
  http.Client get innerClient => _client;

  @override
  Future<FluxAdapterResponse> send(FluxAdapterRequest req) async {
    try {
      final uri = _buildUri(req.url, req.queryParameters);
      final headers = Map<String, String>.from(req.headers);
      final body = req.body;

      final http.Response response;
      switch (req.method) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
        case 'POST':
          response = await _client.post(uri, headers: headers, body: body);
        case 'PUT':
          response = await _client.put(uri, headers: headers, body: body);
        case 'PATCH':
          response = await _client.patch(uri, headers: headers, body: body);
        case 'DELETE':
          response = await _client.delete(uri, headers: headers, body: body);
        default:
          throw UnsupportedError('FluxHttpAdapter: unsupported method "${req.method}"');
      }

      return FluxAdapterResponse(
        statusCode: response.statusCode,
        data: _decode(response.body),
      );
    } on SocketException catch (e) {
      throw FluxAdapterException(
          type: FluxAdapterErrorType.connectionError, originalException: e);
    } on TlsException catch (e) {
      throw FluxAdapterException(
          type: FluxAdapterErrorType.badCertificate, originalException: e);
    } on http.ClientException catch (e) {
      throw FluxAdapterException(
          type: FluxAdapterErrorType.unknown, originalException: e);
    } catch (e) {
      throw FluxAdapterException(
          type: FluxAdapterErrorType.unknown, originalException: e);
    }
  }

  @override
  Future<FluxAdapterResponse> sendMultipart(FluxAdapterMultipartRequest req) async {
    try {
      final uri = _buildUri(req.url, req.queryParameters);
      // Remove Content-Type: http sets it automatically with the multipart boundary
      final headers = Map<String, String>.from(req.headers)
        ..remove('Content-Type')
        ..remove('content-type');

      final request = http.MultipartRequest(req.method, uri)
        ..headers.addAll(headers)
        ..fields.addAll(req.fields);

      for (final file in req.files) {
        request.files.add(
          http.MultipartFile.fromBytes(
            file.field,
            file.bytes,
            filename: file.filename,
          ),
        );
      }

      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);

      return FluxAdapterResponse(
        statusCode: response.statusCode,
        data: _decode(response.body),
      );
    } on SocketException catch (e) {
      throw FluxAdapterException(
          type: FluxAdapterErrorType.connectionError, originalException: e);
    } on http.ClientException catch (e) {
      throw FluxAdapterException(
          type: FluxAdapterErrorType.unknown, originalException: e);
    } catch (e) {
      throw FluxAdapterException(
          type: FluxAdapterErrorType.unknown, originalException: e);
    }
  }

  Uri _buildUri(String url, Map<String, dynamic> queryParameters) {
    var uri = Uri.parse(url);
    if (queryParameters.isNotEmpty) {
      uri = uri.replace(
        queryParameters: queryParameters.map((k, v) => MapEntry(k, '$v')),
      );
    }
    return uri;
  }

  dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }
}
