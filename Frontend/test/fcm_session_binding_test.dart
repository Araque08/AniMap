import 'dart:async';
import 'dart:convert';

import 'package:animap/features/auth/data/fcm_session_binding.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Storage implements SessionStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  late SessionManager session;
  late FcmSessionBinding binding;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;

  setUp(() {
    requests = [];
    respond = (request) async => http.Response(
      jsonEncode({
        'ok': true,
        'data': {'registered': request.method == 'PUT'},
      }),
      200,
    );
    session = SessionManager(
      storage: _Storage(),
      authBaseUrl: 'http://example.invalid/api/auth',
      client: MockClient((_) async => http.Response('{"ok":true}', 200)),
    );
    binding = FcmSessionBinding(
      sessionManager: session,
      client: MockClient((r) async {
        requests.add(r);
        return respond(r);
      }),
    );
    binding.start();
  });

  tearDown(() async {
    await binding.pending;
    binding.dispose();
    session.dispose();
  });

  Future<void> login([String account = 'a']) => session.establishSession(
    accessToken: 'fixture-access-$account',
    refreshToken: 'fixture-refresh-$account',
    role: 'USUARIO',
  );

  test(
    'FCM antes del login espera y solo envia registro a la sesion autenticada',
    () async {
      binding.onRegistration('fixture-fid-a');
      await binding.pending;
      expect(requests, isEmpty);
      await login();
      await binding.pending;
      expect(requests.length, 1);
      expect(requests.single.url.path, '/api/auth/fcm-registration');
      expect(requests.single.headers.containsKey('Authorization'), isTrue);
      expect((jsonDecode(requests.single.body) as Map).keys, [
        'registrationId',
      ]);
    },
  );

  test(
    'login antes de FCM y eventos duplicados solo asocian una vez',
    () async {
      await login();
      binding.onRegistration('fixture-fid-a');
      binding.onRegistration('fixture-fid-a');
      await binding.pending;
      expect(requests.where((r) => r.method == 'PUT').length, 1);
    },
  );

  test(
    'rotacion del identificador retira el anterior y guarda el nuevo',
    () async {
      await login();
      binding.onRegistration('fixture-fid-a');
      await binding.pending;
      binding.onRegistration('fixture-fid-b');
      await binding.pending;
      expect(requests.map((r) => r.method), ['PUT', 'DELETE', 'PUT']);
      expect(
        jsonDecode(requests.last.body)['registrationId'].endsWith('-b'),
        isTrue,
      );
    },
  );

  test(
    'logout retira la asociacion y no vuelve a registrar sin sesion',
    () async {
      await login();
      binding.onRegistration('fixture-fid-a');
      await binding.pending;
      final result = await session.logout();
      await binding.pending;
      expect(result.remoteRevoked, isTrue);
      expect(session.isAuthenticated, isFalse);
      expect(requests.map((r) => r.method), ['PUT', 'DELETE']);
      binding.onRegistration('fixture-fid-b');
      await binding.pending;
      expect(requests.length, 2);
    },
  );

  test('expirar la sesión de API no retira el consentimiento push', () async {
    await login();
    binding.onRegistration('fixture-fid-independent');
    await binding.pending;
    await session.clearLocalSession();
    await binding.pending;
    expect(requests.map((r) => r.method), ['PUT']);
  });

  test(
    'cambio de usuario autentica cada operacion con su JWT capturado',
    () async {
      await login();
      binding.onRegistration('fixture-fid-a');
      await binding.pending;
      await login('b');
      await binding.pending;
      expect(requests.map((r) => r.method), ['PUT', 'DELETE', 'PUT']);
      expect(
        requests[1].headers['Authorization'] ==
            requests[0].headers['Authorization'],
        isTrue,
      );
      expect(
        requests.last.headers['Authorization'] !=
            requests.first.headers['Authorization'],
        isTrue,
      );
    },
  );

  test(
    'respuesta tardia despues de logout no reabre ni conserva la asociacion',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      respond = (r) async {
        if (r.method == 'PUT') {
          started.complete();
          return response.future;
        }
        return http.Response('{"ok":true}', 200);
      };
      await login();
      binding.onRegistration('fixture-fid-a');
      await started.future;
      await session.logout();
      response.complete(
        http.Response('{"ok":true,"data":{"registered":true}}', 200),
      );
      await binding.pending;
      expect(session.isAuthenticated, isFalse);
      expect(requests.map((r) => r.method), ['PUT', 'DELETE']);
    },
  );

  test('un fallo opcional de FCM no invalida ni bloquea el login', () async {
    respond = (_) async => throw Exception('sensitive-transport-detail');
    await login();
    binding.onRegistration('fixture-fid-a');
    await binding.pending;
    expect(session.isAuthenticated, isTrue);
    expect(session.role, 'USUARIO');
    await session.logout();
    await binding.pending;
    expect(session.isAuthenticated, isFalse);
  });

  test(
    'respuesta de la cuenta anterior no invalida ni asocia la cuenta nueva',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var puts = 0;
      respond = (request) async {
        if (request.method == 'PUT' && puts++ == 0) {
          started.complete();
          return response.future;
        }
        return http.Response('{"ok":true,"data":{"registered":true}}', 200);
      };
      await login();
      binding.onRegistration('fixture-fid-a');
      await started.future;
      await login('b');
      response.complete(
        http.Response('{"ok":false,"code":"SESSION_REVOKED"}', 401),
      );
      await binding.pending;
      expect(session.isAuthenticated, isTrue);
      expect(requests.map((r) => r.method), ['PUT', 'DELETE', 'PUT']);
      expect(
        requests.last.headers['Authorization'] !=
            requests.first.headers['Authorization'],
        isTrue,
      );
    },
  );

  test('restaurar sesion asocia un FID recibido antes del bootstrap', () async {
    binding.dispose();
    session.dispose();
    final storage = _Storage();
    await storage.write(SessionManager.refreshTokenKey, 'fixture-refresh');
    session = SessionManager(
      storage: storage,
      authBaseUrl: 'http://example.invalid/api/auth',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'accessToken': 'fixture-access',
              'refreshToken': 'fixture-refresh-rotated',
              'role': 'USUARIO',
            },
          }),
          200,
        ),
      ),
    );
    binding = FcmSessionBinding(
      sessionManager: session,
      client: MockClient((r) async {
        requests.add(r);
        return http.Response('{"ok":true,"data":{"registered":true}}', 200);
      }),
    );
    binding.start();
    binding.onRegistration('fixture-fid-a');
    await binding.pending;
    expect(requests, isEmpty);
    await session.bootstrap();
    await binding.pending;
    expect(session.isAuthenticated, isTrue);
    expect(requests.where((r) => r.method == 'PUT').length, 1);
  });

  test(
    'migracion pendiente o 401 de FCM no invalida la sesion principal',
    () async {
      for (final status in [503, 401]) {
        respond = (_) async => http.Response('{"ok":false}', status);
        await login();
        binding.onRegistration('fixture-fid-a');
        await binding.pending;
        expect(session.isAuthenticated, isTrue);
      }
    },
  );

  test('dispose deja de observar cambios de sesion e identificador', () async {
    binding.dispose();
    await login();
    binding.onRegistration('fixture-fid-a');
    await binding.pending;
    expect(requests, isEmpty);
  });

  test(
    'logout sin red limpia localmente aunque falle la desvinculacion FCM',
    () async {
      binding.dispose();
      session.dispose();
      session = SessionManager(
        storage: _Storage(),
        authBaseUrl: 'http://example.invalid/api/auth',
        client: MockClient((_) async => throw Exception('offline')),
      );
      binding = FcmSessionBinding(
        sessionManager: session,
        client: MockClient((r) async {
          requests.add(r);
          if (r.method == 'DELETE') throw Exception('offline');
          return http.Response('{"ok":true,"data":{"registered":true}}', 200);
        }),
      );
      binding.start();
      await login();
      binding.onRegistration('fixture-fid-a');
      await binding.pending;
      final result = await session.logout();
      await binding.pending;
      expect(result.remoteRevoked, isFalse);
      expect(session.isAuthenticated, isFalse);
      expect(session.authenticatedSessionGeneration, isNull);
      expect(requests.map((r) => r.method), ['PUT', 'DELETE']);
    },
  );
}
