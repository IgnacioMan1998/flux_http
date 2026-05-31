## 0.1.1

### Fixed

- Corrected repository URL in `pubspec.yaml`.

## 0.1.0

### Added

- `FluxHttp` — configurable HTTP client with multi-environment and multi-backend support.
- `FluxResult<T>` — sealed union (`FluxOk` / `FluxErr`) equivalent to `Either<FluxFailure, T>` with no external FP dependency.
  - `fold(onFailure, onSuccess)` — functional Either-style fold.
  - `foldMessage(client, onFailure, onSuccess)` — fold that resolves `FluxFailure` to `FluxMessage` automatically.
  - `map(transform)` — transform the success value without unwrapping (useful in repository layers).
  - `valueOrNull` — returns `T?`, null if `FluxErr`.
  - `failureOrNull` — returns `FluxFailure?`, null if `FluxOk`.
  - `isOk` / `isErr` — boolean type checks.
- `FluxFailure` — structured failure with `statusCode`, `errorType`, `data`, `exception`, `resolvedMessage` and `isNetworkError`.
  - `copyWith` — safe copy without manually repeating all fields.
- `FluxApiBase` — abstract base class for Clean Architecture datasources.
  - `run(path, ...)` — executes `client.request` and resolves the failure in one call.
  - `runMultipart(path, ...)` — same for multipart/form-data uploads.
  - `resolveFailure(result)` — stamps `FluxFailure.resolvedMessage` at the datasource boundary.
- `FluxMockAdapter` — test adapter with zero real network calls.
  - `onGet` / `onPost` / `onPut` / `onPatch` / `onDelete` — register responses by method + URL substring.
  - `onNetworkError` — simulate network-level failures (timeout, connection error, etc.).
  - `onAny` — dynamic handler for conditional or stateful test responses.
- `FluxDioAdapter` — default transport backed by Dio (cancel tokens, certificate pinning).
- `FluxHttpAdapter` — lighter transport backed by `package:http`.
- `FluxAuthInterceptor` — injects JWT on every request and silently refreshes the token on 401.
- `FluxLogInterceptor` — logs request and response details; supports a custom logger sink.
- `FluxInterceptor` — abstract hook with `onRequest`, `onResponse`, and `onError` overrides.
- `FluxErrorMessages` — i18n error strings with English (default) and Spanish (`FluxErrorMessages.spanish`) presets.
- `FluxMessage` — resolved human-readable message with `code` and `message` fields.
- `FluxMethod` — enum for HTTP verbs (`get`, `post`, `put`, `patch`, `delete`).
- `FluxFile` — adapter-agnostic file descriptor for multipart uploads.
