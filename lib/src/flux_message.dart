/// A resolved, human-readable message produced by [FluxHttp.toMessage].
///
/// Equivalent to Kjaia's `AppResponseModel` — carries a `code` and `message`
/// ready to display in the UI.
class FluxMessage {
  const FluxMessage({
    required this.code,
    required this.message,
  });

  /// Short error code (HTTP status as string, or '0' for network-level errors).
  final String code;

  /// Human-readable message in the configured language.
  final String message;

  @override
  String toString() => 'FluxMessage(code: $code, message: $message)';
}
