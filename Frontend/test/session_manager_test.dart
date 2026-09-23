import 'dart:convert';

import 'package:animap/features/auth/data/auth_service.dart';
import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/map/data/map_reports_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'login normal guarda access en memoria y refresh en almacenamiento seguro',
    () async {
      final storage = MemorySessionStorage();
      final manager = SessionManager(storage: storage);
      final service = AuthService(
        sessionManager: manager,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'accessToken': 'access-login',
                'refreshToken': 'refresh-login',
                'user': {'nombre': 'Prueba', 'rol': 'USUARIO'},
              },
            }),
            200,
          ),
        ),
      );
      await service.login(
        email: 'test@example.invalid',
        password: 'unused-in-test',
        deviceId: 'device-test',
      );
      expect(manager.accessToken, 'access-login');
      expect(manager.role, 'USUARIO');
      expect(
        await storage.read(SessionManager.refreshTokenKey),
        'refresh-login',
      );
    },
  );

  test('deviceId se conserva estable entre lecturas', () async {
    final storage = MemorySessionStorage();
    final first = SessionManager(storage: storage);
    final idA = await first.getDeviceId();
    final second = SessionManager(storage: storage);
    expect(await second.getDeviceId(), idA);
  });

  test('bootstrap sin refresh entra a Login', () async {
    final manager = SessionManager(storage: MemorySessionStorage());
    await manager.bootstrap();
    expect(manager.status, SessionStatus.unauthenticated);
  });

  test('bootstrap con refresh válido rota y restaura sesión', () async {
    final storage = MemorySessionStorage({
      SessionManager.refreshTokenKey: 'token-a',
    });
    final manager = SessionManager(
      storage: storage,
      client: refreshClient(access: 'access-b', refresh: 'token-b'),
    );
    await manager.bootstrap();
    expect(manager.status, SessionStatus.authenticated);
    expect(manager.accessToken, 'access-b');
    expect(await storage.read(SessionManager.refreshTokenKey), 'token-b');
  });

  for (final code in const [
    'REFRESH_TOKEN_INVALID',
    'REFRESH_TOKEN_EXPIRED',
    'SESSION_REVOKED',
    'ACCOUNT_INVALID',
    'ACCOUNT_ROLE_INVALID',
  ]) {
    test('$code elimina sesión local de forma controlada', () async {
      final storage = MemorySessionStorage({
        SessionManager.refreshTokenKey: 'stored',
      });
      final manager = SessionManager(
        storage: storage,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': false,
              'code': code,
              'message': 'Sesión inválida',
            }),
            code == 'ACCOUNT_INVALID' ? 403 : 401,
          ),
        ),
      );
      await manager.bootstrap();
      expect(manager.status, SessionStatus.unauthenticated);
      expect(await storage.read(SessionManager.refreshTokenKey), isNull);
    });
  }

  test(
    'error de red durante refresh conserva credencial y permite reintentar',
    () async {
      final storage = MemorySessionStorage({
        SessionManager.refreshTokenKey: 'stored',
      });
      final manager = SessionManager(
        storage: storage,
        client: MockClient((_) async => throw Exception('offline')),
      );
      await manager.bootstrap();
      expect(manager.status, SessionStatus.connectionError);
      expect(await storage.read(SessionManager.refreshTokenKey), 'stored');
    },
  );

  test('HTTP 500 durante refresh conserva credencial', () async {
    final storage = MemorySessionStorage({
      SessionManager.refreshTokenKey: 'stored',
    });
    final manager = SessionManager(
      storage: storage,
      client: MockClient((_) async => http.Response('{"ok":false}', 500)),
    );
    await manager.bootstrap();
    expect(manager.status, SessionStatus.connectionError);
    expect(await storage.read(SessionManager.refreshTokenKey), 'stored');
  });

  test('access válido ejecuta petición sin refresh', () async {
    var refreshCalls = 0;
    final storage = MemorySessionStorage();
    final manager = SessionManager(storage: storage);
    await manager.establishSession(
      accessToken: 'valid',
      refreshToken: 'refresh',
    );
    final client = AuthenticatedHttpClient(
      sessionManager: manager,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) refreshCalls++;
        expect(request.headers['authorization'], 'Bearer valid');
        return http.Response('{"ok":true}', 200);
      }),
    );
    expect(
      (await client.get(Uri.parse('http://test/private'))).statusCode,
      200,
    );
    expect(refreshCalls, 0);
  });

  test('access expirado renueva y repite la petición original una vez', () async {
    var privateCalls = 0;
    var refreshCalls = 0;
    final storage = MemorySessionStorage({
      SessionManager.refreshTokenKey: 'refresh-a',
    });
    late final SessionManager manager;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/refresh')) {
        refreshCalls++;
        return http.Response(
          '{"ok":true,"data":{"accessToken":"access-b","refreshToken":"refresh-b","role":"USUARIO"}}',
          200,
        );
      }
      privateCalls++;
      if (request.headers['authorization'] == 'Bearer access-a') {
        return http.Response('{"code":"ACCESS_TOKEN_EXPIRED"}', 401);
      }
      return http.Response('{"ok":true}', 200);
    });
    manager = SessionManager(storage: storage, client: mock);
    await manager.establishSession(
      accessToken: 'access-a',
      refreshToken: 'refresh-a',
    );
    final client = AuthenticatedHttpClient(
      sessionManager: manager,
      client: mock,
    );
    expect(
      (await client.get(Uri.parse('http://test/private'))).statusCode,
      200,
    );
    expect(privateCalls, 2);
    expect(refreshCalls, 1);
  });

  test('varias respuestas 401 simultáneas comparten un solo refresh', () async {
    var refreshCalls = 0;
    final storage = MemorySessionStorage({
      SessionManager.refreshTokenKey: 'refresh-a',
    });
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/refresh')) {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(
          '{"ok":true,"data":{"accessToken":"access-b","refreshToken":"refresh-b","role":"USUARIO"}}',
          200,
        );
      }
      if (request.headers['authorization'] == 'Bearer access-a') {
        return http.Response('{"code":"ACCESS_TOKEN_EXPIRED"}', 401);
      }
      return http.Response('{"ok":true}', 200);
    });
    final manager = SessionManager(storage: storage, client: mock);
    await manager.establishSession(
      accessToken: 'access-a',
      refreshToken: 'refresh-a',
    );
    final client = AuthenticatedHttpClient(
      sessionManager: manager,
      client: mock,
    );
    final responses = await Future.wait([
      client.get(Uri.parse('http://test/private/one')),
      client.get(Uri.parse('http://test/private/two')),
      client.get(Uri.parse('http://test/private/three')),
    ]);
    expect(responses.every((response) => response.statusCode == 200), isTrue);
    expect(refreshCalls, 1);
  });

  test('401 tardío reutiliza la rotación completada sin otro refresh', () async {
    var refreshCalls = 0;
    final storage = MemorySessionStorage({
      SessionManager.refreshTokenKey: 'refresh-a',
    });
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/refresh')) {
        refreshCalls++;
        return http.Response(
          '{"ok":true,"data":{"accessToken":"access-b","refreshToken":"refresh-b","role":"USUARIO"}}',
          200,
        );
      }
      if (request.headers['authorization'] == 'Bearer access-a') {
        if (request.url.path.endsWith('/slow')) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        return http.Response('{"code":"ACCESS_TOKEN_EXPIRED"}', 401);
      }
      return http.Response('{"ok":true}', 200);
    });
    final manager = SessionManager(storage: storage, client: mock);
    await manager.establishSession(
      accessToken: 'access-a',
      refreshToken: 'refresh-a',
    );
    final client = AuthenticatedHttpClient(
      sessionManager: manager,
      client: mock,
    );
    final responses = await Future.wait([
      client.get(Uri.parse('http://test/private/fast')),
      client.get(Uri.parse('http://test/private/slow')),
    ]);
    expect(responses.every((response) => response.statusCode == 200), isTrue);
    expect(refreshCalls, 1);
  });

  test('mapa renueva access expirado y carga sin error recuperable', () async {
    var refreshCalls = 0;
    final storage = MemorySessionStorage({
      SessionManager.refreshTokenKey: 'refresh-a',
    });
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/refresh')) {
        refreshCalls++;
        return http.Response(
          '{"ok":true,"data":{"accessToken":"access-b","refreshToken":"refresh-b","role":"USUARIO"}}',
          200,
        );
      }
      if (request.headers['authorization'] == 'Bearer access-a') {
        return http.Response('{"code":"ACCESS_TOKEN_EXPIRED"}', 401);
      }
      return http.Response('{"ok":true,"data":[]}', 200);
    });
    final manager = SessionManager(storage: storage, client: mock);
    await manager.establishSession(
      accessToken: 'access-a',
      refreshToken: 'refresh-a',
    );
    final reportsClient = MapReportsClient(
      client: AuthenticatedHttpClient(sessionManager: manager, client: mock),
    );
    final response = await reportsClient.getReports(
      Uri.parse('http://test/api/map/reports'),
    );
    expect(response.statusCode, 200);
    expect(refreshCalls, 1);
  });

  test('segundo 401 no crea loop y termina la sesión', () async {
    final storage = MemorySessionStorage({
      SessionManager.refreshTokenKey: 'refresh-a',
    });
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/refresh')) {
        return http.Response(
          '{"ok":true,"data":{"accessToken":"access-b","refreshToken":"refresh-b","role":"USUARIO"}}',
          200,
        );
      }
      return http.Response('{"code":"ACCESS_TOKEN_INVALID"}', 401);
    });
    final manager = SessionManager(storage: storage, client: mock);
    await manager.establishSession(
      accessToken: 'access-a',
      refreshToken: 'refresh-a',
    );
    final client = AuthenticatedHttpClient(
      sessionManager: manager,
      client: mock,
    );
    await expectLater(
      client.get(Uri.parse('http://test/private')),
      throwsA(isA<SessionInvalidException>()),
    );
    expect(await storage.read(SessionManager.refreshTokenKey), isNull);
  });

  test('logout remoto revoca y siempre limpia sesión local', () async {
    var logoutCalls = 0;
    final storage = MemorySessionStorage({
      SessionManager.refreshTokenKey: 'refresh',
    });
    final manager = SessionManager(
      storage: storage,
      client: MockClient((request) async {
        logoutCalls++;
        return http.Response('{"ok":true}', 200);
      }),
    );
    await manager.establishSession(
      accessToken: 'access',
      refreshToken: 'refresh',
    );
    final result = await manager.logout();
    expect(result.remoteRevoked, isTrue);
    expect(logoutCalls, 1);
    expect(manager.accessToken, isNull);
    expect(await storage.read(SessionManager.refreshTokenKey), isNull);
  });

  test('refresh adopta el rol vigente y avisa para cambiar de panel', () async {
    final storage = MemorySessionStorage();
    final manager = SessionManager(
      storage: storage,
      client: MockClient(
        (_) async => http.Response(
          '{"ok":true,"data":{"accessToken":"access-b","refreshToken":"refresh-b","role":"ADMINISTRADOR"}}',
          200,
        ),
      ),
    );
    await manager.establishSession(
      accessToken: 'access-a',
      refreshToken: 'refresh-a',
      role: 'USUARIO',
    );
    String? changedTo;
    manager.onRoleChanged = (role) => changedTo = role;
    await manager.refreshAccessToken();
    expect(manager.role, 'ADMINISTRADOR');
    expect(changedTo, 'ADMINISTRADOR');
    expect(await storage.read(SessionManager.refreshTokenKey), 'refresh-b');
  });

  test(
    'logout sin red sigue siendo local y no finge revocación remota',
    () async {
      final storage = MemorySessionStorage({
        SessionManager.refreshTokenKey: 'refresh',
      });
      final manager = SessionManager(
        storage: storage,
        client: MockClient((_) async => throw Exception('offline')),
      );
      await manager.establishSession(
        accessToken: 'access',
        refreshToken: 'refresh',
      );
      final result = await manager.logout();
      expect(result.remoteRevoked, isFalse);
      expect(manager.status, SessionStatus.unauthenticated);
      expect(await storage.read(SessionManager.refreshTokenKey), isNull);
    },
  );
}

MockClient refreshClient({required String access, required String refresh}) {
  return MockClient(
    (_) async => http.Response(
      jsonEncode({
        'ok': true,
        'data': {
          'accessToken': access,
          'refreshToken': refresh,
          'role': 'USUARIO',
        },
      }),
      200,
    ),
  );
}

class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
