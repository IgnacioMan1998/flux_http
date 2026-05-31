// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:flux_http/flux_http.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class PostModel {
  const PostModel({required this.id, required this.title, required this.body});

  final int id;
  final String title;
  final String body;

  factory PostModel.fromJson(dynamic json) => PostModel(
        id: json['id'] as int,
        title: json['title'] as String,
        body: json['body'] as String,
      );

  @override
  String toString() => 'PostModel(id: $id, title: "$title")';
}

// ─── Fake token storage (simulates FlutterSecureStorage / AppSessionManagement)

String? _accessToken = 'valid-token-abc';

Future<String?> getToken() async => _accessToken;

Future<String?> doRefresh() async {
  // Simulates a successful refresh returning a new token.
  // Return null to simulate an expired session.
  print('  [auth] refreshing token...');
  _accessToken = 'refreshed-token-xyz';
  return _accessToken;
}

void onSessionExpired() {
  print('  [auth] session expired — redirect to /login');
}

// ─── Setup ────────────────────────────────────────────────────────────────────

final client = FluxHttp(
  environment: 'prod',
  baseUrls: {
    'dev':  {'main': 'https://dev.jsonplaceholder.typicode.com/'},
    'prod': {'main': 'https://jsonplaceholder.typicode.com/'},
  },
  defaultHeaders: {'Content-Type': 'application/json'},
  errorMessages: FluxErrorMessages.spanish,
  interceptors: [
    // 1. Auth — injects token on every request, refreshes on 401
    FluxAuthInterceptor(
      getToken: getToken,
      refreshToken: doRefresh,
      onRefreshFailed: onSessionExpired,
    ),
    // 2. Log — prints request/response (disable in production)
    const FluxLogInterceptor(logRequestBody: true),
  ],
);

// ─── API ──────────────────────────────────────────────────────────────────────

Future<FluxResult<PostModel>> fetchPostById(int id) {
  return client.request<PostModel>(
    'posts/$id',
    onSuccess: PostModel.fromJson,
  );
}

Future<FluxResult<PostModel>> createPost({
  required String title,
  required String body,
}) {
  return client.request<PostModel>(
    'posts',
    method: FluxMethod.post,
    body: {'title': title, 'body': body, 'userId': 1},
    onSuccess: PostModel.fromJson,
  );
}

Future<FluxResult<Map<String, dynamic>>> uploadAttachment({
  required int postId,
  required Uint8List bytes,
  required String filename,
}) {
  return client.multipart<Map<String, dynamic>>(
    'https://httpbin.org/post',
    fields: {'postId': '$postId'},
    files: [
      FluxFile(
        field: 'attachment',
        bytes: bytes,
        filename: filename,
        contentType: 'image/jpeg',
      ),
    ],
    onSuccess: (json) => Map<String, dynamic>.from(json as Map),
  );
}

// ─── Main ─────────────────────────────────────────────────────────────────────

Future<void> main() async {
  // Right — GET success (Authorization header injected by FluxAuthInterceptor)
  print('─── GET /posts/1 → Right ───');
  final r1 = await fetchPostById(1);
  r1.fold(
    (f) => print('Left  [${client.toMessage(f).code}]: ${client.toMessage(f).message}'),
    (p) => print('Right: $p'),
  );

  // Left — 404
  print('\n─── GET /posts/99999 → Left (404) ───');
  final r2 = await fetchPostById(99999);
  r2.fold(
    (f) => print('Left  [${client.toMessage(f).code}]: ${client.toMessage(f).message}'),
    (p) => print('Right: $p'),
  );

  // Right — POST
  print('\n─── POST /posts → Right ───');
  final r3 = await createPost(title: 'flux_http', body: 'Interceptors work!');
  r3.fold(
    (f) => print('Left  [${client.toMessage(f).code}]: ${client.toMessage(f).message}'),
    (p) => print('Right: $p'),
  );

  // Right — multipart (Authorization header also injected via onRequest)
  print('\n─── POST multipart → Right ───');
  final r4 = await uploadAttachment(
    postId: 1,
    bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
    filename: 'photo.jpg',
  );
  r4.fold(
    (f) => print('Left  [${client.toMessage(f).code}]: ${client.toMessage(f).message}'),
    (b) => print('Right — files: ${(b['files'] as Map?)?.keys.toList()}'),
  );
}
