import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_manager.dart';

class AuthenticatedHttpClient {
  static final AuthenticatedHttpClient instance = AuthenticatedHttpClient();

  final SessionManager sessionManager;
  final http.Client _client;

  AuthenticatedHttpClient({SessionManager? sessionManager, http.Client? client})
    : sessionManager = sessionManager ?? SessionManager.instance,
      _client = client ?? http.Client();

  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    bool optionalAuthentication = false,
  }) => _execute(
    (authHeaders) => _client.get(url, headers: {...?headers, ...authHeaders}),
    optionalAuthentication: optionalAuthentication,
  );

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _execute(
    (authHeaders) =>
        _client.post(url, headers: {...?headers, ...authHeaders}, body: body),
  );

  Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _execute(
    (authHeaders) =>
        _client.patch(url, headers: {...?headers, ...authHeaders}, body: body),
  );

  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _execute(
    (authHeaders) =>
        _client.put(url, headers: {...?headers, ...authHeaders}, body: body),
  );

  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _execute(
    (authHeaders) =>
        _client.delete(url, headers: {...?headers, ...authHeaders}, body: body),
  );

  Future<http.Response> sendMultipart(
    Future<http.MultipartRequest> Function(String accessToken) requestBuilder,
  ) async {
    Future<http.Response> send(String token) async {
      final request = await requestBuilder(token);
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }

    var token = sessionManager.accessToken;
    if (token == null || token.isEmpty) {
      token = await sessionManager.refreshAccessToken();
    }
    var response = await send(token);
    if (!_requiresRefresh(response)) return response;
    final currentToken = sessionManager.accessToken;
    token =
        currentToken != null && currentToken.isNotEmpty && currentToken != token
        ? currentToken
        : await sessionManager.refreshAccessToken();
    response = await send(token);
    if (_requiresRefresh(response)) {
      await sessionManager.invalidateSession(code: _authCode(response));
    }
    return response;
  }

  Future<http.Response> _execute(
    Future<http.Response> Function(Map<String, String> authHeaders) operation, {
    bool optionalAuthentication = false,
  }) async {
    var token = sessionManager.accessToken;
    if ((token == null || token.isEmpty) && !optionalAuthentication) {
      token = await sessionManager.refreshAccessToken();
    }
    var response = await operation(
      token == null || token.isEmpty
          ? const {}
          : {'Authorization': 'Bearer $token'},
    );
    if (!_requiresRefresh(response) ||
        (optionalAuthentication && (token == null || token.isEmpty))) {
      return response;
    }
    final currentToken = sessionManager.accessToken;
    token =
        currentToken != null && currentToken.isNotEmpty && currentToken != token
        ? currentToken
        : await sessionManager.refreshAccessToken();
    response = await operation({'Authorization': 'Bearer $token'});
    if (_requiresRefresh(response)) {
      await sessionManager.invalidateSession(code: _authCode(response));
    }
    return response;
  }

  bool _requiresRefresh(http.Response response) {
    if (response.statusCode != 401) return false;
    try {
      final body = jsonDecode(response.body);
      final code = body is Map ? body['code']?.toString() : null;
      return code == null ||
          code == 'ACCESS_TOKEN_EXPIRED' ||
          code == 'ACCESS_TOKEN_INVALID' ||
          code == 'ACCESS_TOKEN_REQUIRED';
    } catch (_) {
      return true;
    }
  }

  String? _authCode(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body is Map ? body['code']?.toString() : null;
    } catch (_) {
      return null;
    }
  }
}
