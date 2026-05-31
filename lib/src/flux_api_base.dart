import 'flux_adapter.dart';
import 'flux_failure.dart';
import 'flux_http.dart';
import 'flux_method.dart';

/// Abstract base class for API datasources in Clean Architecture.
///
/// Inject a [FluxHttp] instance via the constructor and call [resolveFailure]
/// at the end of every API method. This stamps a human-readable message on
/// [FluxFailure.resolvedMessage] so that repository and presentation layers
/// never need to call `client.toMessage(failure)` manually.
///
/// This mirrors the Kjaia `responseFailure()` pattern — the error type stays
/// as `FluxResult<T>` throughout all layers, but the failure already carries
/// the display-ready string once it leaves the datasource.
///
/// ## Setup
/// ```dart
/// class UserApi extends FluxApiBase {
///   UserApi(super.client);
///
///   Future<FluxResult<UserModel>> fetchUser(int id) async {
///     final result = await client.request<UserModel>(
///       'users/$id',
///       onSuccess: UserModel.fromJson,
///     );
///     return resolveFailure(result); // stamps resolvedMessage if error
///   }
///
///   Future<FluxResult<List<UserModel>>> fetchAll({
///     required int page,
///   }) async {
///     final result = await client.request<List<UserModel>>(
///       'users',
///       queryParameters: {'page': page},
///       onSuccess: (data) =>
///           (data as List).map((e) => UserModel.fromJson(e)).toList(),
///     );
///     return resolveFailure(result);
///   }
/// }
/// ```
///
/// ## Repository layer (no toMessage needed)
/// ```dart
/// class UserRepositoryImpl extends UserRepository {
///   UserRepositoryImpl({required this.api});
///   final UserApi api;
///
///   @override
///   Future<FluxResult<UserEntity>> fetchUser(int id) =>
///       api.fetchUser(id); // failure already has resolvedMessage
/// }
/// ```
///
/// ## Provider / ViewModel layer
/// ```dart
/// final result = await userUsecase.fetchUser(id);
///
/// // Option A — foldMessage (reads resolvedMessage automatically)
/// result.foldMessage(
///   client,
///   (msg) => state = state.copyWith(error: msg.message),
///   (user) => state = state.copyWith(user: user),
/// );
///
/// // Option B — direct access
/// result.fold(
///   (f) => showSnackbar(f.resolvedMessage ?? 'Error'),
///   (user) => state = state.copyWith(user: user),
/// );
/// ```
abstract class FluxApiBase {
  const FluxApiBase(this.client);

  /// The configured HTTP client for this datasource.
  final FluxHttp client;

  /// Resolves any [FluxFailure] in [result] by stamping a human-readable
  /// message on [FluxFailure.resolvedMessage]. [FluxOk] results pass through
  /// unchanged.
  ///
  /// Call this at the end of every API method — once per request, at the
  /// datasource boundary — so upper layers receive a failure that already
  /// carries a display-ready message.
  FluxResult<T> resolveFailure<T>(FluxResult<T> result) {
    return switch (result) {
      FluxOk() => result,
      FluxErr(:final failure) => FluxErr(
          failure.copyWith(resolvedMessage: client.toMessage(failure).message),
        ),
    };
  }

  /// Executes a request and resolves any failure in a single call — equivalent
  /// to `resolveFailure(await client.request(...))` but without the two steps.
  ///
  /// All parameters mirror [FluxHttp.request]. Use this instead of calling
  /// `client.request` + `resolveFailure` separately in every API method.
  ///
  /// ```dart
  /// class UserApi extends FluxApiBase {
  ///   UserApi(super.client);
  ///
  ///   Future<FluxResult<UserModel>> fetchUser(int id) => run(
  ///     'users/$id',
  ///     onSuccess: UserModel.fromJson,
  ///   );
  ///
  ///   Future<FluxResult<UserModel>> createUser(Map<String, dynamic> data) => run(
  ///     'users',
  ///     method: FluxMethod.post,
  ///     body: data,
  ///     onSuccess: UserModel.fromJson,
  ///   );
  /// }
  /// ```
  Future<FluxResult<T>> run<T>(
    String path, {
    FluxMethod method = FluxMethod.get,
    String backend = 'main',
    Map<String, String> headers = const {},
    Map<String, dynamic> queryParameters = const {},
    Map<String, dynamic> body = const {},
    Object? cancelToken,
    required T Function(dynamic responseBody) onSuccess,
  }) async =>
      resolveFailure(
        await client.request<T>(
          path,
          method: method,
          backend: backend,
          headers: headers,
          queryParameters: queryParameters,
          body: body,
          cancelToken: cancelToken,
          onSuccess: onSuccess,
        ),
      );

  /// Executes a multipart request and resolves any failure in a single call —
  /// equivalent to `resolveFailure(await client.multipart(...))`.
  ///
  /// ```dart
  /// Future<FluxResult<ProfileModel>> uploadAvatar(Uint8List bytes) => runMultipart(
  ///   'users/me/avatar',
  ///   files: [FluxFile(field: 'avatar', bytes: bytes, filename: 'avatar.jpg')],
  ///   onSuccess: ProfileModel.fromJson,
  /// );
  /// ```
  Future<FluxResult<T>> runMultipart<T>(
    String path, {
    FluxMethod method = FluxMethod.post,
    String backend = 'main',
    Map<String, String> headers = const {},
    Map<String, String> fields = const {},
    List<FluxFile> files = const [],
    Map<String, dynamic> queryParameters = const {},
    required T Function(dynamic responseBody) onSuccess,
  }) async =>
      resolveFailure(
        await client.multipart<T>(
          path,
          method: method,
          backend: backend,
          headers: headers,
          fields: fields,
          files: files,
          queryParameters: queryParameters,
          onSuccess: onSuccess,
        ),
      );
}
