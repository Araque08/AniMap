import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/auth/presentation/session_gate.dart';
import 'package:animap/features/user/presentation/pages/profile_page.dart';
import 'package:animap/widgets/top_menu_animap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'logout desde menú lateral revoca, va a Login y limpia el stack',
    (tester) async {
      final harness = await LogoutHarness.create();
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/home',
          routes: {
            '/home': (_) => Scaffold(
              drawer: AniMapSideMenu(sessionManager: harness.manager),
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  child: const Text('Abrir menú'),
                ),
              ),
            ),
            '/login': (_) => const Scaffold(body: Text('Login destino')),
          },
        ),
      );
      await tester.tap(find.text('Abrir menú'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cerrar sesión?'), findsOneWidget);
      expect(
        find.text('¿Estás seguro de que deseas cerrar tu sesión en AniMap?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Login destino'), findsOneWidget);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
      expect(harness.logoutCalls, 1);
      expect(
        await harness.storage.read(SessionManager.refreshTokenKey),
        isNull,
      );
    },
  );

  testWidgets('cancelar logout desde menú conserva la sesión', (tester) async {
    final harness = await LogoutHarness.create();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: AniMapSideMenu(sessionManager: harness.manager),
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              child: const Text('Abrir menú'),
            ),
          ),
        ),
        routes: {'/login': (_) => const Scaffold(body: Text('Login destino'))},
      ),
    );
    await tester.tap(find.text('Abrir menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Login destino'), findsNothing);
    expect(harness.logoutCalls, 0);
    expect(
      await harness.storage.read(SessionManager.refreshTokenKey),
      'refresh-test',
    );
  });

  testWidgets('logout desde Perfil usa el mismo flujo y va a Login', (
    tester,
  ) async {
    final harness = await LogoutHarness.create();
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          sessionManager: harness.manager,
          profileLoader: () async => {
            'nombre': 'Usuario temporal',
            'email': 'test@example.invalid',
            'telefono': '3000000000',
            'foto_url': null,
          },
        ),
        routes: {'/login': (_) => const Scaffold(body: Text('Login destino'))},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cerrar sesión?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Login destino'), findsOneWidget);
    expect(harness.logoutCalls, 1);
    expect(await harness.storage.read(SessionManager.refreshTokenKey), isNull);
  });

  testWidgets('abrir app después de logout permanece en Login', (tester) async {
    final harness = await LogoutHarness.create();
    await harness.manager.logout();
    final reopened = SessionManager(
      storage: harness.storage,
      client: harness.client,
    );
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: SessionGate(sessionManager: reopened)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Iniciar Sesión'), findsWidgets);
    expect(reopened.status, SessionStatus.unauthenticated);
  });

  testWidgets('cerrar, reabrir y reiniciar Flutter conserva sesión válida', (
    tester,
  ) async {
    final storage = MemorySessionStorage()
      ..values[SessionManager.refreshTokenKey] = 'refresh-a';
    var refreshCalls = 0;
    final client = MockClient((request) async {
      refreshCalls++;
      return http.Response(
        '{"ok":true,"data":{"accessToken":"access","refreshToken":"refresh-next","role":"USUARIO"}}',
        200,
      );
    });

    Future<void> openWithFreshMemory() async {
      final manager = SessionManager(storage: storage, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionGate(
            sessionManager: manager,
            authenticatedBuilder: (_) =>
                const Scaffold(body: Text('Home autenticado')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home autenticado'), findsOneWidget);
      expect(manager.status, SessionStatus.authenticated);
    }

    await openWithFreshMemory();
    await tester.pumpWidget(const SizedBox.shrink());
    await openWithFreshMemory();
    expect(refreshCalls, 2);
  });

  testWidgets('error transitorio conserva sesión y ofrece Reintentar', (
    tester,
  ) async {
    final storage = MemorySessionStorage()
      ..values[SessionManager.refreshTokenKey] = 'refresh';
    var online = false;
    final manager = SessionManager(
      storage: storage,
      client: MockClient((_) async {
        if (!online) throw Exception('offline');
        return http.Response(
          '{"ok":true,"data":{"accessToken":"access","refreshToken":"next","role":"USUARIO"}}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          sessionManager: manager,
          authenticatedBuilder: (_) =>
              const Scaffold(body: Text('Home autenticado')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(await storage.read(SessionManager.refreshTokenKey), 'refresh');
    online = true;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Home autenticado'), findsOneWidget);
  });
}

class LogoutHarness {
  LogoutHarness._(this.storage, this.client, this.manager);

  final MemorySessionStorage storage;
  final MockClient client;
  final SessionManager manager;
  int logoutCalls = 0;

  static Future<LogoutHarness> create() async {
    final storage = MemorySessionStorage();
    late LogoutHarness harness;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/logout')) harness.logoutCalls++;
      return http.Response('{"ok":true}', 200);
    });
    final manager = SessionManager(storage: storage, client: client);
    harness = LogoutHarness._(storage, client, manager);
    await manager.establishSession(
      accessToken: 'access-test',
      refreshToken: 'refresh-test',
    );
    return harness;
  }
}

class MemorySessionStorage implements SessionStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
