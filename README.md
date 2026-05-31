# flux_http

A configurable, multi-environment, multi-backend HTTP client for Dart and Flutter.  
Returns `FluxResult<T>` (a built-in sealed Either) — no codegen, no external FP library required.

---

## Features

- **Multi-environment** — switch between `dev`, `staging`, `prod` with a single field
- **Multi-backend** — different base URLs per environment (main API, CDN, payments, etc.)
- **Pluggable transport** — Dio (default), `package:http`, or any custom `FluxAdapter`
- **Pluggable interceptors** — JWT auto-attach + 401 refresh, logging, or custom middleware
- **Sealed `FluxResult<T>`** — `FluxOk` / `FluxErr` with `fold`, `map`, `foldMessage`
- **`FluxApiBase`** — base class for Clean Architecture datasources with `run` / `runMultipart`
- **`FluxMockAdapter`** — test adapter with zero real network calls
- **i18n error messages** — English (default) and Spanish built-in; fully customizable

---

## Installation

```yaml
dependencies:
  flux_http: ^0.1.0
```

---

## Quick start

```dart
import 'package:flux_http/flux_http.dart';

final client = FluxHttp(
  environment: 'prod',
  baseUrls: {
    'dev':  {'main': 'https://dev.api.myapp.com/v1/'},
    'prod': {'main': 'https://api.myapp.com/v1/'},
  },
);

final result = await client.request<UserModel>(
  'users/me',
  onSuccess: UserModel.fromJson,
);

result.fold(
  (failure) => print(client.toMessage(failure).message),
  (user)    => print(user.name),
);
```

---

## Configuration

### Full setup with auth + logging

```dart
final client = FluxHttp(
  environment: 'prod',                        // which key to pick from baseUrls
  baseUrls: {
    'dev': {
      'main':     'https://dev.api.myapp.com/v1/',
      'payments': 'https://dev.payments.myapp.com/v1/',
    },
    'prod': {
      'main':     'https://api.myapp.com/v1/',
      'payments': 'https://payments.myapp.com/v1/',
    },
  },
  defaultHeaders: {
    'Content-Type': 'application/json',
    'X-Client-Id':  'my-flutter-app',
  },
  errorMessages: FluxErrorMessages.spanish,   // or const FluxErrorMessages() for English
  interceptors: [
    FluxAuthInterceptor(
      getToken:       () => secureStorage.read('access_token'),
      refreshToken:   () async {
        final res = await authApi.refresh();
        return res.valueOrNull?.accessToken;  // null = session expired
      },
      onRefreshFailed: () => router.go('/login'),
    ),
    if (kDebugMode) const FluxLogInterceptor(logRequestBody: true),
  ],
);
```

### Switching environments at runtime

```dart
// Read from environment variable, build flavor, or remote config:
final client = FluxHttp(
  environment: const String.fromEnvironment('ENV', defaultValue: 'dev'),
  baseUrls: { ... },
);
```

### Custom error messages (any language)

```dart
const myMessages = FluxErrorMessages(
  timeout:      'Tiempo de espera agotado.',
  network:      'Sin conexión a internet.',
  unauthorized: 'Sesión expirada.',
  notFound:     'Recurso no encontrado.',
  serverError:  'Error del servidor.',
  unknown:      'Error inesperado.',
  // remaining fields keep their English defaults
);

final client = FluxHttp(
  environment: 'prod',
  baseUrls: { ... },
  errorMessages: myMessages,
);
```

---

## Making requests

### GET

```dart
final result = await client.request<List<PostModel>>(
  'posts',
  queryParameters: {'page': 1, 'limit': 20},
  onSuccess: (data) => (data as List).map(PostModel.fromJson).toList(),
);
```

### POST / PUT / PATCH / DELETE

```dart
final result = await client.request<PostModel>(
  'posts',
  method: FluxMethod.post,
  body: {'title': 'Hello', 'body': 'World', 'userId': 1},
  onSuccess: PostModel.fromJson,
);
```

### Target a secondary backend

```dart
final result = await client.request<PaymentModel>(
  'checkout',
  method: FluxMethod.post,
  backend: 'payments',          // uses baseUrls[environment]['payments']
  body: {'amount': 9900},
  onSuccess: PaymentModel.fromJson,
);
```

### File upload (multipart)

```dart
final bytes = await File('photo.jpg').readAsBytes();

final result = await client.multipart<ProfileModel>(
  'users/me/avatar',
  fields: {'userId': '42'},
  files: [
    FluxFile(
      field:       'avatar',
      bytes:       bytes,
      filename:    'photo.jpg',
      contentType: 'image/jpeg',
    ),
  ],
  onSuccess: ProfileModel.fromJson,
);
```

---

## Handling results

`FluxResult<T>` is a sealed class with two variants: `FluxOk<T>` (success) and `FluxErr<T>` (failure).

### fold — functional style

```dart
result.fold(
  (failure) => showSnackbar(client.toMessage(failure).message),
  (user)    => setState(() => _user = user),
);
```

### foldMessage — skip `toMessage` boilerplate

```dart
// When using FluxApiBase.run(), resolvedMessage is pre-populated.
result.foldMessage(
  client,
  (msg)  => state = state.copyWith(error: msg.message),   // FluxMessage
  (user) => state = state.copyWith(user: user),
);
```

### Pattern matching (Dart 3)

```dart
switch (result) {
  case FluxOk(:final value):
    setState(() => _posts = value);
  case FluxErr(:final failure) when failure.statusCode == 404:
    showNotFound();
  case FluxErr(:final failure):
    showSnackbar(client.toMessage(failure).message);
}
```

### Convenience getters

```dart
final user    = result.valueOrNull;    // T?          — null if FluxErr
final failure = result.failureOrNull;  // FluxFailure? — null if FluxOk
final isOk    = result.isOk;           // bool
```

### map — transform without unwrapping

```dart
// In RepositoryImpl: convert model → entity without touching the error path
final entityResult = result.map((model) => model.toEntity()); // FluxResult<UserEntity>
```

---

## Clean Architecture — `FluxApiBase`

`FluxApiBase` is the recommended way to structure API datasources. It pre-resolves
error messages at the datasource boundary so repository and presentation layers
receive a `FluxResult` where `failure.resolvedMessage` is already set.

### Datasource (data layer)

```dart
class UserApi extends FluxApiBase {
  UserApi(super.client);

  // run() = request() + resolveFailure() in one call
  Future<FluxResult<UserModel>> fetchUser(int id) => run(
    'users/$id',
    onSuccess: UserModel.fromJson,
  );

  Future<FluxResult<List<UserModel>>> fetchAll({int page = 1}) => run(
    'users',
    queryParameters: {'page': page, 'limit': 20},
    onSuccess: (data) => (data as List).map(UserModel.fromJson).toList(),
  );

  Future<FluxResult<UserModel>> createUser(Map<String, dynamic> data) => run(
    'users',
    method: FluxMethod.post,
    body: data,
    onSuccess: UserModel.fromJson,
  );

  Future<FluxResult<ProfileModel>> uploadAvatar(Uint8List bytes) => runMultipart(
    'users/me/avatar',
    files: [FluxFile(field: 'avatar', bytes: bytes, filename: 'avatar.jpg')],
    onSuccess: ProfileModel.fromJson,
  );
}
```

### Repository (domain layer)

```dart
class UserRepositoryImpl implements UserRepository {
  UserRepositoryImpl({required this.api});
  final UserApi api;

  @override
  Future<FluxResult<UserEntity>> fetchUser(int id) async {
    // map() converts model → entity without re-wrapping
    return (await api.fetchUser(id)).map((m) => m.toEntity());
  }

  @override
  Future<FluxResult<List<UserEntity>>> fetchAll({int page = 1}) async {
    return (await api.fetchAll(page: page))
        .map((list) => list.map((m) => m.toEntity()).toList());
  }
}
```

### Provider / ViewModel (presentation layer)

```dart
class UserProvider extends ChangeNotifier {
  UserProvider({required this.usecase, required this.client});

  final UserUsecase usecase;
  final FluxHttp client;

  UserState state = const UserState();

  Future<void> loadUser(int id) async {
    state = state.copyWith(isLoading: true);
    notifyListeners();

    final result = await usecase.fetchUser(id);

    // foldMessage resolves the error message automatically
    result.foldMessage(
      client,
      (msg)  => state = state.copyWith(isLoading: false, error: msg.message),
      (user) => state = state.copyWith(isLoading: false, user: user),
    );

    notifyListeners();
  }
}
```

---

## Interceptors

### `FluxAuthInterceptor` — JWT + silent refresh

```dart
FluxAuthInterceptor(
  getToken:        () => secureStorage.read('access_token'),
  refreshToken:    () async {
    final res = await authApi.refresh();      // returns new token or null
    if (res != null) {
      await secureStorage.write('access_token', res);
    }
    return res;
  },
  onRefreshFailed: () {
    secureStorage.deleteAll();
    router.go('/login');
  },
  // Optional — override defaults:
  tokenHeader: 'Authorization',   // default
  tokenPrefix: 'Bearer',          // default
)
```

Flow: `onRequest` injects the token → server returns `401` → `refreshToken()` is called once → request is retried with the new token → if refresh returns `null`, `onRefreshFailed()` fires and the `401` surfaces as `FluxErr`.

### `FluxLogInterceptor` — request/response logging

```dart
FluxLogInterceptor(
  logRequest:     true,            // default
  logResponse:    true,            // default
  logErrors:      true,            // default
  logRequestBody: false,           // default — enable only in debug
  logger: (msg) => myLogger.d(msg), // optional — defaults to print()
)
```

### Custom interceptor

```dart
class LanguageInterceptor extends FluxInterceptor {
  const LanguageInterceptor(this.locale);
  final String locale;

  @override
  FutureOr<FluxAdapterRequest> onRequest(FluxAdapterRequest request) =>
      request.copyWith(
        headers: {...request.headers, 'Accept-Language': locale},
      );
}
```

---

## Transport adapters

### `FluxDioAdapter` (default)

Supports cancel tokens, certificate pinning, and Dio's transformer pipeline.

```dart
final dio = Dio()
  ..options.connectTimeout = const Duration(seconds: 10)
  ..options.receiveTimeout = const Duration(seconds: 30);

final client = FluxHttp(
  environment: 'prod',
  baseUrls: { ... },
  adapter: FluxDioAdapter(dio: dio),
);

// Access the inner Dio instance later:
(client.adapter as FluxDioAdapter).innerDio;
```

### `FluxHttpAdapter` — lighter alternative

```dart
final client = FluxHttp(
  environment: 'prod',
  baseUrls: { ... },
  adapter: FluxHttpAdapter(),
);
```

### Custom adapter

```dart
class ChopperFluxAdapter implements FluxAdapter {
  @override
  Future<FluxAdapterResponse> send(FluxAdapterRequest req) async { ... }

  @override
  Future<FluxAdapterResponse> sendMultipart(FluxAdapterMultipartRequest req) async { ... }
}
```

---

## Testing with `FluxMockAdapter`

```dart
import 'package:flux_http/flux_http.dart';
import 'package:test/test.dart';

FluxHttp makeTestClient(FluxMockAdapter mock) => FluxHttp(
  environment: 'test',
  baseUrls: {'test': {'main': 'https://mock/'}},
  errorMessages: FluxErrorMessages.spanish,
  adapter: mock,
);

void main() {
  group('UserApi', () {
    test('returns UserModel on 200', () async {
      final mock = FluxMockAdapter()
        ..onGet('users/1', body: {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'});

      final api    = UserApi(makeTestClient(mock));
      final result = await api.fetchUser(1);

      expect(result.isOk, true);
      expect(result.valueOrNull?.name, 'Alice');
    });

    test('returns resolved error message on 404', () async {
      final mock = FluxMockAdapter()
        ..onGet('users/99', statusCode: 404, body: {'error': 'Not found'});

      final api    = UserApi(makeTestClient(mock));
      final result = await api.fetchUser(99);

      expect(result.isErr, true);
      expect(result.failureOrNull?.statusCode, 404);
      expect(result.failureOrNull?.resolvedMessage, isNotNull);
    });

    test('returns network error on timeout', () async {
      final mock = FluxMockAdapter()
        ..onNetworkError('users', type: FluxAdapterErrorType.connectionTimeout);

      final api    = UserApi(makeTestClient(mock));
      final result = await api.fetchUser(1);

      expect(result.isErr, true);
      expect(result.failureOrNull?.isNetworkError, true);
    });

    test('onAny — dynamic handler for stateful responses', () async {
      int calls = 0;
      final mock = FluxMockAdapter()
        ..onAny((req) {
          calls++;
          return FluxAdapterResponse(statusCode: 200, data: {'id': calls, 'name': 'User $calls'});
        });

      final api = UserApi(makeTestClient(mock));
      await api.fetchUser(1);
      await api.fetchUser(2);

      expect(calls, 2);
    });
  });
}
```

---

## API reference

### `FluxHttp`

| Constructor param | Type                               | Default                                | Description                  |
| ----------------- | ---------------------------------- | -------------------------------------- | ---------------------------- |
| `environment`     | `String`                           | required                               | Active key in `baseUrls`     |
| `baseUrls`        | `Map<String, Map<String, String>>` | required                               | URLs per environment/backend |
| `defaultHeaders`  | `Map<String, String>`              | `{'Content-Type': 'application/json'}` | Merged into every request    |
| `errorMessages`   | `FluxErrorMessages`                | English                                | Human-readable error strings |
| `interceptors`    | `List<FluxInterceptor>`            | `[]`                                   | Middleware stack             |
| `adapter`         | `FluxAdapter?`                     | `FluxDioAdapter()`                     | HTTP transport               |

### `FluxResult<T>` members

| Member                                      | Type            | Description                          |
| ------------------------------------------- | --------------- | ------------------------------------ |
| `fold(onFailure, onSuccess)`                | `R`             | Either-style fold                    |
| `foldMessage(client, onFailure, onSuccess)` | `R`             | Fold with pre-resolved `FluxMessage` |
| `map(transform)`                            | `FluxResult<R>` | Transform success value              |
| `valueOrNull`                               | `T?`            | Value if `FluxOk`, else `null`       |
| `failureOrNull`                             | `FluxFailure?`  | Failure if `FluxErr`, else `null`    |
| `isOk` / `isErr`                            | `bool`          | Type check                           |

### `FluxFailure` fields

| Field             | Type                    | Description                                        |
| ----------------- | ----------------------- | -------------------------------------------------- |
| `statusCode`      | `int?`                  | HTTP status code (4xx/5xx)                         |
| `errorType`       | `FluxAdapterErrorType?` | Network-level error type                           |
| `data`            | `Object?`               | Raw response body                                  |
| `exception`       | `Object?`               | Underlying exception                               |
| `resolvedMessage` | `String?`               | Pre-resolved display string (set by `FluxApiBase`) |
| `isNetworkError`  | `bool`                  | `true` when no HTTP response was received          |
# flux_http
