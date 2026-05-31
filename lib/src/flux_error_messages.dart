/// Human-readable error messages returned by [FluxHttp.toMessage].
///
/// All fields are optional — defaults are provided in English.
/// Override them to localize to any language (e.g. Spanish for Kjaia).
class FluxErrorMessages {
  const FluxErrorMessages({
    this.timeout =
        'The request timed out. Please try again.',
    this.network =
        'A network error occurred. Please check your internet connection.',
    this.badCertificate =
        'A certificate error occurred. Please check your device security settings.',
    this.badResponse =
        'We are having technical difficulties. Please try again in a moment.',
    this.cancelled =
        'The request was cancelled. Please try again.',
    this.unauthorized =
        'Unauthorized.',
    this.forbidden =
        'You do not have permission to access this resource.',
    this.notFound =
        'The requested resource was not found.',
    this.methodNotAllowed =
        'Method not allowed. Please verify the request and try again.',
    this.serverError =
        'A server error occurred. Please try again later.',
    this.serviceUnavailable =
        'The server is currently unavailable. Please try again later.',
    this.unknown =
        'An unexpected error occurred. Please try again.',
  });

  final String timeout;
  final String network;
  final String badCertificate;
  final String badResponse;
  final String cancelled;
  final String unauthorized;
  final String forbidden;
  final String notFound;
  final String methodNotAllowed;
  final String serverError;
  final String serviceUnavailable;
  final String unknown;

  /// Spanish preset — ready to use without writing all strings.
  static const spanish = FluxErrorMessages(
    timeout: 'Se ha agotado el tiempo de espera. Por favor, inténtalo de nuevo.',
    network: 'Error de red. Por favor, comprueba tu conexión a Internet.',
    badCertificate: 'Error de certificado. Verifica la configuración de seguridad de tu dispositivo.',
    badResponse: 'Estamos teniendo dificultades técnicas. Por favor, intenta en unos momentos.',
    cancelled: 'La solicitud fue cancelada. Por favor, inténtalo más tarde.',
    unauthorized: 'No autorizado.',
    forbidden: 'No tienes permiso para acceder a este recurso.',
    notFound: 'No se encontró el recurso solicitado.',
    methodNotAllowed: 'Método no permitido. Por favor, verifica la solicitud.',
    serverError: 'Error en el servidor. Por favor, inténtalo más tarde.',
    serviceUnavailable: 'El servidor no está disponible. Por favor, inténtalo más tarde.',
    unknown: 'Error inesperado. Por favor, inténtalo de nuevo.',
  );
}
