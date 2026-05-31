import '../flux_adapter.dart';

/// Test-only [FluxAdapter] that returns pre-configured responses without
/// making real network calls.
///
/// Register handlers by HTTP method + URL substring (or a wildcard fallback
/// via [onAny]). Handlers are evaluated in registration order — first match wins.
///
/// ## Setup
/// ```dart
/// final mock = FluxMockAdapter()
///   ..onGet('/users/1', body: {'id': 1, 'name': 'Alice'})
///   ..onPost('/sessions', statusCode: 401, body: {'error': 'Unauthorized'})
///   ..onAny((req) => FluxAdapterResponse(statusCode: 200, data: {}));
///
/// final client = FluxHttp(
///   environment: 'test',
///   baseUrls: {'test': {'main': 'https://mock/'}},
///   adapter: mock,
/// );
/// ```
///
/// ## Example test
/// ```dart
/// test('fetchUser returns UserModel on 200', () async {
///   final mock = FluxMockAdapter()
///     ..onGet('/users/42', body: {'id': 42, 'name': 'Bob'});
///
///   final client = FluxHttp(
///     environment: 'test',
///     baseUrls: {'test': {'main': 'https://mock/'}},
///     adapter: mock,
///   );
///
///   final result = await client.request<UserModel>(
///     'users/42',
///     onSuccess: UserModel.fromJson,
///   );
///
///   expect(result.isOk, true);
///   expect((result as FluxOk).value.name, 'Bob');
/// });
/// ```
class FluxMockAdapter implements FluxAdapter {
  final _handlers = <_MockHandler>[];

  /// Register a response for GET requests whose URL contains [urlContains].
  FluxMockAdapter onGet(
    String urlContains, {
    required Object? body,
    int statusCode = 200,
  }) =>
      _register('GET', urlContains, statusCode, body);

  /// Register a response for POST requests whose URL contains [urlContains].
  FluxMockAdapter onPost(
    String urlContains, {
    required Object? body,
    int statusCode = 200,
  }) =>
      _register('POST', urlContains, statusCode, body);

  /// Register a response for PUT requests whose URL contains [urlContains].
  FluxMockAdapter onPut(
    String urlContains, {
    required Object? body,
    int statusCode = 200,
  }) =>
      _register('PUT', urlContains, statusCode, body);

  /// Register a response for PATCH requests whose URL contains [urlContains].
  FluxMockAdapter onPatch(
    String urlContains, {
    required Object? body,
    int statusCode = 200,
  }) =>
      _register('PATCH', urlContains, statusCode, body);

  /// Register a response for DELETE requests whose URL contains [urlContains].
  FluxMockAdapter onDelete(
    String urlContains, {
    required Object? body,
    int statusCode = 200,
  }) =>
      _register('DELETE', urlContains, statusCode, body);

  /// Register a dynamic handler for any request not matched by other handlers.
  ///
  /// The handler receives the full [FluxAdapterRequest] and must return a
  /// [FluxAdapterResponse]. Use this for conditional or stateful responses.
  ///
  /// ```dart
  /// int callCount = 0;
  /// mock.onAny((req) {
  ///   callCount++;
  ///   return FluxAdapterResponse(statusCode: 200, data: {'calls': callCount});
  /// });
  /// ```
  FluxMockAdapter onAny(
    FluxAdapterResponse Function(FluxAdapterRequest request) handler,
  ) {
    _handlers.add(_MockHandler(null, null, handler));
    return this;
  }

  /// Simulates a network-level error (no HTTP response) for requests whose
  /// URL contains [urlContains].
  ///
  /// [type] defaults to [FluxAdapterErrorType.connectionError].
  ///
  /// ```dart
  /// final mock = FluxMockAdapter()
  ///   ..onNetworkError('/users', type: FluxAdapterErrorType.connectionTimeout);
  ///
  /// // The FluxHttp client will return FluxErr with errorType set,
  /// // and FluxApiBase.run will stamp the resolved message automatically.
  /// final result = await userApi.fetchUser(1);
  /// expect(result.isErr, true);
  /// expect(result.failureOrNull?.isNetworkError, true);
  /// ```
  FluxMockAdapter onNetworkError(
    String urlContains, {
    String? method,
    FluxAdapterErrorType type = FluxAdapterErrorType.connectionError,
  }) {
    _handlers.add(
      _MockHandler(
        method,
        urlContains,
        (_) => throw FluxAdapterException(type: type),
      ),
    );
    return this;
  }

  FluxMockAdapter _register(
    String method,
    String urlContains,
    int statusCode,
    Object? body,
  ) {
    _handlers.add(
      _MockHandler(
        method,
        urlContains,
        (_) => FluxAdapterResponse(statusCode: statusCode, data: body),
      ),
    );
    return this;
  }

  @override
  Future<FluxAdapterResponse> send(FluxAdapterRequest request) async {
    for (final handler in _handlers) {
      if (handler.matches(request.method, request.url)) {
        return handler.build(request);
      }
    }
    throw StateError(
      '[FluxMockAdapter] No handler registered for '
      '${request.method} ${request.url}.\n'
      'Register one with onGet / onPost / onPut / onPatch / onDelete / onAny.',
    );
  }

  @override
  Future<FluxAdapterResponse> sendMultipart(
    FluxAdapterMultipartRequest request,
  ) async {
    // Multipart is treated like a regular request for mock purposes.
    final synthetic = FluxAdapterRequest(
      url: request.url,
      method: request.method,
      headers: request.headers,
      queryParameters: request.queryParameters,
    );
    return send(synthetic);
  }
}

// ─── Internal ────────────────────────────────────────────────────────────────

class _MockHandler {
  const _MockHandler(this.method, this.urlContains, this.build);

  /// `null` acts as a wildcard (matches any method/URL).
  final String? method;
  final String? urlContains;
  final FluxAdapterResponse Function(FluxAdapterRequest) build;

  bool matches(String reqMethod, String reqUrl) {
    final methodOk = method == null || reqMethod == method;
    final urlOk = urlContains == null || reqUrl.contains(urlContains!);
    return methodOk && urlOk;
  }
}
