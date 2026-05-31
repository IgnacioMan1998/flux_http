# Kjaia Mobile — Arquitectura de referencia para `flux_http`

> Este documento describe la arquitectura real de **Kjaia Mobile** (`kjaia_mobile`),
> el proyecto Flutter del que `flux_http` toma sus patrones y convenciones.
> Sirve como fuente de verdad para decisiones de diseño del paquete.

---

## Stack

| Capa                  | Tecnología                                                        |
| --------------------- | ----------------------------------------------------------------- |
| UI                    | Flutter · Material 3 · Poppins                                    |
| State management      | `StateNotifier<T>` custom + `provider` (`ChangeNotifierProvider`) |
| HTTP                  | `AppDio` (wrapper sobre `dio`)                                    |
| Resultado HTTP        | `Either<AppResponseModel, T>` de `dartz`                          |
| DI                    | `get_it` (manual, sin codegen)                                    |
| Navegación            | `go_router` (rutas planas)                                        |
| Almacenamiento seguro | `flutter_secure_storage`                                          |
| Base de datos local   | `sqflite` (Kjaia.db)                                              |

---

## Clean Architecture por módulo

Cada feature vive en `lib/app/[feature]/` y sigue exactamente esta estructura:

```
feature/
├── data/
│   ├── datasources/
│   │   ├── apis/          ← Clases *API  (reciben AppDio, retornan Either)
│   │   └── device/        ← SQLite, SecureStorage
│   ├── models/            ← Extienden entities (herencia directa)
│   └── repositories_impl/ ← Implementaciones concretas
├── domain/
│   ├── entities/          ← Dart puro, sin dependencias externas
│   ├── repositories/      ← Interfaces abstractas
│   └── usecases/          ← Wrapper fino sobre repository
└── presentation/
    ├── providers/         ← StateNotifier<State> + State (Equatable)
    ├── screens/           ← Screen crea Provider; _View lo consume
    └── widgets/           ← Widgets del feature
```

---

## Cadena de datos completa

```
AppDio
  └─→ *API                         Either<AppDioFailure, R>
        └─→ responseFailure()       Either<AppResponseModel, T>  ← convierte el error
              └─→ *RepositoryImpl   Either<AppResponseModel, T>
                    └─→ *Usecase    Either<AppResponseModel, T>
                          └─→ *Provider.fold()
```

### Descripción de cada eslabón

#### 1. `AppDio` — `lib/core/http/app_dio.dart`

Wrapper sobre `Dio`. Es el equivalente de `FluxHttp` en este paquete.

```dart
class AppDio {
  AppDio({required Dio dio, required AppEnvironment appEnvironment});

  Future<Either<AppDioFailure, R>> request<R>(
    String path, {
    HttpMethod method = HttpMethod.get,
    Map<String, String> header = const {},
    Map<String, dynamic> queryParameter = const {},
    Map<String, dynamic> body = const {},
    Apps apps = Apps.main,
    CancelToken? cancelToken,
    required R Function(dynamic responseBody) onSuccess,
  }) async { ... }

  Future<Either<AppDioFailure, R>> requestMultipart<R>(...) async { ... }
}
```

- Siempre retorna `Either<AppDioFailure, R>` — **nunca lanza excepciones al caller**.
- `right(onSuccess(response.data))` cuando `statusCode >= 200 && < 300`.
- `left(AppDioFailure(...))` en cualquier otro caso.
- Multi-entorno vía `AppEnvironment` (`dev`, `test`, `prod`) y `Apps` (`main`, `paypal`, etc.).

#### 2. `AppDioFailure` — `lib/core/http/app_dio_failure.dart`

```dart
class AppDioFailure {
  final int? statusCode;
  final Object? exception;
  final Object? data;
}
```

Error de bajo nivel, aún ligado a Dio. No sale de la capa `data`.

#### 3. `responseFailure()` — `lib/core/errors/app_response_error.dart`

Función pura que convierte `AppDioFailure` → `Either<AppResponseModel, T>`.
Es el punto donde los errores de red se convierten en mensajes legibles.

```dart
Either<AppResponseModel, T> responseFailure<T>(AppDioFailure failure) {
  if (failure.exception is DioException && failure.statusCode == null) {
    // Errores de red: timeout, badCertificate, connectionError, cancel…
    return Left(AppResponseModel(code: '0', message: AppResponseHttpMessages.xxx));
  }
  // Errores HTTP (4xx/5xx)
  return Left(AppResponseModel(
    code: '${failure.statusCode}',
    message: _messageForCode(failure.statusCode),
  ));
}
```

#### 4. `AppResponseModel` — `lib/core/errors/app_response_model.dart`

El "Left" que llega al Provider. Equivale a `FluxMessage` + `FluxFailure` combinados.

```dart
class AppResponseModel {
  final String code;    // HTTP status o '0' para errores de red
  final String message; // Mensaje en español listo para mostrar al usuario
}
```

#### 5. `*API` — `data/datasources/apis/`

Recibe `AppDio`, llama `request()` y convierte el resultado con `responseFailure()`.

```dart
class CourseAPI {
  CourseAPI(this._appDio);
  final AppDio _appDio;

  Future<Either<AppResponseModel, List<CourseModel>>> fetchCourses({
    required String sessionId,
    required PaginationSharedEntity params,
  }) async {
    final response = await _appDio.request<List<CourseModel>>(
      'courses',
      header: {'Authorization': 'Bearer $sessionId'},
      queryParameter: params.toQueryParameters(),
      onSuccess: (data) => (data['items'] as List)
          .map((e) => CourseModel.fromJson(e))
          .toList(),
    );
    // Fold: error → Left con mensaje legible; éxito → Right con modelo
    return response.fold(responseFailure, (data) => Right(data));
  }
}
```

**Regla:** La API **nunca** retorna `Future<void>`. Siempre `Future<Either<AppResponseModel, T>>`.

#### 6. `*RepositoryImpl` — `data/repositories_impl/`

Implementa la interfaz del domain. Puede agregar lógica antes del API call
(p.ej. validar sesión activa, leer caché local).

```dart
class CourseRepositoryImpl extends CourseRepository {
  @override
  Future<Either<AppResponseModel, CourseEntity>> fetchCourseById({
    required int id,
  }) async {
    final sessionId = await appSessionManagement.getSessionId;
    // Guard clause → Left sin hacer la llamada de red
    if (!await appSessionManagement.hasSession(sessionId: sessionId ?? '')) {
      return Left(AppResponseModel(
        code: AppMessagesDeviceError.responseCodeError,
        message: AppMessagesDeviceError.sessionExpired,
      ));
    }
    final response = await courseApi.fetchCourseById(sessionId: sessionId!, id: id);
    return response.fold((failure) => Left(failure), (data) => Right(data));
  }
}
```

#### 7. `*Usecase` — `domain/usecases/`

Wrapper fino — delega directo al repository. Sin lógica adicional.

```dart
class CourseUsecase {
  CourseUsecase({required this.courseRepository});
  final CourseRepository courseRepository;

  Future<Either<AppResponseModel, CourseEntity>> fetchCourseById({
    required int id,
  }) => courseRepository.fetchCourseById(id: id);
}
```

#### 8. `*Provider` — `presentation/providers/`

Llama al usecase, hace `.fold()` y actualiza el `State` con `copyWith()`.

```dart
class CourseProvider extends StateNotifier<CourseState> {
  Future<Either<AppResponseModel, List<CourseEntity>>> loadCourses() async {
    state = state.copyWith(isLoading: true);

    final resp = await courseUsecase.fetchCourses(params: PaginationSharedEntity());

    state = state.copyWith(isLoading: false);
    return resp.fold(
      (err) {
        // Puede mostrar snackbar, actualizar estado de error, etc.
        return Left(err);
      },
      (data) {
        state = state.copyWith(courses: data);
        return Right(data);
      },
    );
  }
}
```

---

## Entity → Model (herencia directa)

```dart
// domain/entities/course_entity.dart — Dart puro
class CourseEntity {
  final int idCourse;
  final String name;
  final double price;
  // ...decenas de campos...
  const CourseEntity({required this.idCourse, required this.name, ...});
}

// data/models/course_model.dart — agrega fromJson()
class CourseModel extends CourseEntity {
  const CourseModel({required super.idCourse, required super.name, ...});

  factory CourseModel.fromJson(Map<String, dynamic> json) => CourseModel(
    idCourse: json['id'],
    name: json['name'],
    // ...
  );
}
```

**Regla:** Model **extiende** Entity (herencia). No usa composición ni `fromEntity()` salvo necesidad real.

---

## State + Provider

```dart
// CourseState — Equatable con copyWith
class CourseState extends Equatable {
  final bool isLoading;
  final List<CourseEntity> courses;
  final CourseEntity? course;
  // ...

  const CourseState({this.isLoading = false, this.courses = const [], ...});

  CourseState copyWith({bool? isLoading, List<CourseEntity>? courses, ...}) =>
      CourseState(isLoading: isLoading ?? this.isLoading, ...);

  @override
  List<Object?> get props => [isLoading, courses, course, ...];
}
```

---

## Screen → \_View pattern

```dart
// Screen crea el Provider e inyecta dependencias de GetIt
class CourseDetailScreen extends StatelessWidget {
  static const routeName = '/course-detail';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CourseDetailProvider(
        CourseDetailState(),
        courseUsecase: GetIt.instance(),
        // ...resto de dependencias
      )..onInit(course: course),
      child: const _CourseDetailView(),
    );
  }
}

// _View consume el estado (privado, solo lee)
class _CourseDetailView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    // ...usa provider.state
  }
}
```

---

## Inyección de dependencias — `di.dart`

```dart
final di = GetIt.instance;

void setupDI() {
  // Orden: AppDio → APIs → Repos → UseCases → Providers
  di.registerLazySingleton<AppDio>(() => AppDio(dio: Dio(), appEnvironment: AppEnvironment.prod));
  di.registerLazySingleton<CourseAPI>(() => CourseAPI(di()));
  di.registerLazySingleton<CourseRepository>(() => CourseRepositoryImpl(courseApi: di(), ...));
  di.registerLazySingleton<CourseUsecase>(() => CourseUsecase(courseRepository: di()));
  di.registerFactory<CourseProvider>(() => CourseProvider(CourseState(), courseUsecase: di()));
}
```

| Tipo         | Método GetIt            | Razón                         |
| ------------ | ----------------------- | ----------------------------- |
| Providers    | `registerFactory`       | State fresco en cada pantalla |
| UseCases     | `registerLazySingleton` | Sin estado interno            |
| Repositories | `registerLazySingleton` | Sin estado interno            |
| APIs         | `registerLazySingleton` | Comparten AppDio              |
| Services     | `registerLazySingleton` | Singleton global              |

---

## Equivalencias Kjaia ↔ flux_http

| Kjaia                           | flux_http                                   | Notas                         |
| ------------------------------- | ------------------------------------------- | ----------------------------- |
| `AppDio`                        | `FluxHttp`                                  | Orquestador principal         |
| `AppDioFailure`                 | `FluxAdapterException`                      | Error de transporte interno   |
| `AppResponseModel`              | `FluxMessage`                               | Código + mensaje legible      |
| `Either<AppResponseModel, T>`   | `FluxResult<T>` (`FluxOk`/`FluxErr`)        | Sin dependencia de `dartz`    |
| `responseFailure()`             | `FluxHttp.toMessage()`                      | Convierte error → mensaje     |
| `CourseModel.fromJson`          | `onSuccess: PostModel.fromJson`             | Mapeo en el callback          |
| Interceptors Dio via `innerDio` | `FluxAuthInterceptor`, `FluxLogInterceptor` | Primera clase en flux_http    |
| `HttpMethod` enum               | `FluxMethod` enum                           | GET, POST, PUT, PATCH, DELETE |
| `Apps` enum (main, paypal…)     | `backend:` param (`'main'`, `'cdn'`…)       | Multi-backend                 |
| `AppEnvironment` enum           | `environment:` param (`'dev'`, `'prod'`)    | Multi-entorno                 |
