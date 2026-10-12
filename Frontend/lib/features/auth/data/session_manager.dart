import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';
import 'session_storage.dart';

enum SessionStatus { checking, authenticated, unauthenticated, connectionError }

class SessionInvalidException implements Exception {
  final String message;
  final String? code;
  const SessionInvalidException(this.message, [this.code]);

  @override
  String toString() => message;
}

class SessionConnectionException implements Exception {
  final String message;
  const SessionConnectionException(this.message);

  @override
  String toString() => message;
}

class LogoutResult {
  final bool remoteRevoked;
  final bool hadStoredSession;

  const LogoutResult({
    required this.remoteRevoked,
    required this.hadStoredSession,
  });
}

class SessionManager extends ChangeNotifier {
  static const refreshTokenKey = 'animap_refresh_token';
  static const deviceIdKey = 'animap_device_id';
  static final SessionManager instance = SessionManager();

  final SessionStorage storage;
  final http.Client _client;
  final String authBaseUrl;

  String? _accessToken;
  String? _role;
  SessionStatus _status = SessionStatus.checking;
  Future<String>? _refreshInFlight;
  Future<void> _tokenStorageTail = Future<void>.value();
  int _sessionEpoch = 0;
  VoidCallback? onSessionInvalid;
  void Function(String role)? onRoleChanged;

  SessionManager({
    SessionStorage? storage,
    http.Client? client,
    String? authBaseUrl,
  }) : storage = storage ?? const SecureSessionStorage(),
       _client = client ?? http.Client(),
       authBaseUrl = authBaseUrl ?? '${ApiConfig.current.baseUrl}/auth';

  String? get accessToken => _accessToken;
  String? get role => _role;
  SessionStatus get status => _status;
  bool get isAuthenticated => _status == SessionStatus.authenticated;

  Future<String> getDeviceId() async {
    final stored = await storage.read(deviceIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final value = base64UrlEncode(bytes).replaceAll('=', '');
    await storage.write(deviceIdKey, value);
    return value;
  }

  Future<void> establishSession({
    required String accessToken,
    required String refreshToken,
    String? role,
  }) async {
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const SessionInvalidException(
        'El servidor devolvió una sesión inválida',
      );
    }
    final epoch = ++_sessionEpoch;
    _refreshInFlight = null;
    await _queueTokenStorage(() async {
      _requireEpoch(epoch);
      await storage.write(refreshTokenKey, refreshToken);
      _requireEpoch(epoch);
    });
    _requireEpoch(epoch);
    _accessToken = accessToken;
    _role = role;
    _setStatus(SessionStatus.authenticated);
  }

  Future<void> bootstrap() async {
    final epoch = _sessionEpoch;
    _setStatus(SessionStatus.checking);
    try {
      final refreshToken = await storage.read(refreshTokenKey);
      _requireEpoch(epoch);
      if (refreshToken == null || refreshToken.isEmpty) {
        _accessToken = null;
        _role = null;
        _setStatus(SessionStatus.unauthenticated);
        return;
      }
      await _refresh(refreshToken, epoch, notifyInvalid: false);
    } on SessionInvalidException {
      if (_sessionEpoch == epoch) await clearLocalSession();
    } on SessionConnectionException {
      if (_sessionEpoch == epoch) _setStatus(SessionStatus.connectionError);
    } catch (_) {
      if (_sessionEpoch == epoch) _setStatus(SessionStatus.connectionError);
    }
  }

  Future<String> refreshAccessToken() {
    final pending = _refreshInFlight;
    if (pending != null) return pending;
    final epoch = _sessionEpoch;
    late final Future<String> future;
    future = _refreshStoredToken(epoch).whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
    _refreshInFlight = future;
    return future;
  }

  Future<String> _refreshStoredToken(int epoch) async {
    final refreshToken = await storage.read(refreshTokenKey);
    _requireEpoch(epoch);
    if (refreshToken == null || refreshToken.isEmpty) {
      await _invalidateLocalSession();
      throw const SessionInvalidException('No existe una sesión renovable');
    }
    return _refresh(refreshToken, epoch);
  }

  Future<String> _refresh(
    String refreshToken,
    int epoch, {
    bool notifyInvalid = true,
  }) async {
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$authBaseUrl/refresh'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      _requireEpoch(epoch);
      throw const SessionConnectionException(
        'No fue posible conectar con el servidor. Intenta nuevamente.',
      );
    }

    _requireEpoch(epoch);
    final body = _decode(response);
    if (response.statusCode == 200 && body['ok'] == true) {
      final accessToken = body['data']?['accessToken']?.toString();
      final nextRefreshToken = body['data']?['refreshToken']?.toString();
      final nextRole = body['data']?['role']?.toString().trim().toUpperCase();
      if (accessToken == null ||
          accessToken.isEmpty ||
          nextRefreshToken == null ||
          nextRefreshToken.isEmpty) {
        throw const SessionConnectionException(
          'El servidor devolvió una respuesta de sesión incompleta.',
        );
      }
      if (nextRole != 'USUARIO' && nextRole != 'ADMINISTRADOR') {
        throw const SessionConnectionException(
          'El servidor no devolvió un rol válido.',
        );
      }
      final previousRole = _role;
      final wasAuthenticated = _status == SessionStatus.authenticated;
      await _queueTokenStorage(() async {
        _requireEpoch(epoch);
        await storage.write(refreshTokenKey, nextRefreshToken);
        _requireEpoch(epoch);
      });
      _requireEpoch(epoch);
      _accessToken = accessToken;
      _role = nextRole;
      _setStatus(SessionStatus.authenticated);
      if (previousRole != _role && wasAuthenticated) {
        notifyListeners();
        onRoleChanged?.call(_role!);
      }
      return accessToken;
    }

    final code = body['code']?.toString();
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        _terminalCodes.contains(code)) {
      await _invalidateLocalSession(notify: notifyInvalid);
      throw SessionInvalidException(
        body['message']?.toString() ?? 'La sesión ya no es válida',
        code,
      );
    }
    throw SessionConnectionException(
      body['message']?.toString() ??
          'No fue posible renovar la sesión. Intenta nuevamente.',
    );
  }

  Future<LogoutResult> logout() async {
    final epoch = ++_sessionEpoch;
    _refreshInFlight = null;
    bool remoteRevoked = false;
    bool hadStoredSession = false;
    try {
      await _tokenStorageTail;
      if (_sessionEpoch != epoch) {
        return const LogoutResult(
          remoteRevoked: false,
          hadStoredSession: false,
        );
      }
      final refreshToken = await storage.read(refreshTokenKey);
      if (_sessionEpoch != epoch) {
        return const LogoutResult(
          remoteRevoked: false,
          hadStoredSession: false,
        );
      }
      hadStoredSession = refreshToken != null && refreshToken.isNotEmpty;
      if (hadStoredSession) {
        try {
          final response = await _client
              .post(
                Uri.parse('$authBaseUrl/logout'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode({'refreshToken': refreshToken}),
              )
              .timeout(const Duration(seconds: 15));
          final body = _decode(response);
          remoteRevoked = response.statusCode == 200 && body['ok'] == true;
        } catch (_) {
          remoteRevoked = false;
        }
      }
    } finally {
      if (_sessionEpoch == epoch) await clearLocalSession();
    }
    return LogoutResult(
      remoteRevoked: remoteRevoked,
      hadStoredSession: hadStoredSession,
    );
  }

  Future<void> clearLocalSession() async {
    _sessionEpoch += 1;
    _refreshInFlight = null;
    _accessToken = null;
    _role = null;
    _setStatus(SessionStatus.unauthenticated);
    await _queueTokenStorage(() => storage.delete(refreshTokenKey));
  }

  Future<void> invalidateSession({String? code}) async {
    await _invalidateLocalSession();
    throw SessionInvalidException('La sesión ya no es válida', code);
  }

  void clearAccessTokenFromMemory() {
    _accessToken = null;
  }

  Future<void> _invalidateLocalSession({bool notify = true}) async {
    await clearLocalSession();
    if (notify) onSessionInvalid?.call();
  }

  void _requireEpoch(int epoch) {
    if (_sessionEpoch != epoch) {
      throw const SessionInvalidException(
        'La sesión cambió durante la renovación',
      );
    }
  }

  Future<void> _queueTokenStorage(Future<void> Function() operation) {
    final pending = _tokenStorageTail.then((_) => operation());
    _tokenStorageTail = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return pending;
  }

  void _setStatus(SessionStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  static const _terminalCodes = {
    'REFRESH_TOKEN_INVALID',
    'REFRESH_TOKEN_EXPIRED',
    'SESSION_REVOKED',
    'ACCOUNT_INVALID',
    'ACCOUNT_ROLE_INVALID',
  };

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}
