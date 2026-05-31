/// flux_http — configurable multi-environment HTTP client for Dart & Flutter.
///
/// Returns [FluxResult] (sealed Ok/Err) without requiring any FP library.
/// Supports multiple environments, multiple backends, multipart uploads,
/// pluggable adapters (Dio / package:http / custom), pluggable interceptors
/// (auth token + 401 refresh, logging, custom), and built-in i18n error messages.
library;

export 'src/adapters/flux_dio_adapter.dart';
export 'src/adapters/flux_http_adapter.dart';
export 'src/adapters/flux_mock_adapter.dart';
export 'src/flux_adapter.dart';
export 'src/flux_api_base.dart';
export 'src/flux_error_messages.dart';
export 'src/flux_failure.dart';
export 'src/flux_http.dart';
export 'src/flux_interceptor.dart';
export 'src/flux_message.dart';
export 'src/flux_method.dart';
export 'src/interceptors/flux_auth_interceptor.dart';
export 'src/interceptors/flux_log_interceptor.dart';
