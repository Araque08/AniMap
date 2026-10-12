import 'dart:async';
import 'dart:convert';

import 'package:animap/config/api_config.dart';
import 'package:animap/features/admin/data/users/user_service.dart';
import 'package:animap/features/admin/presentation/pages/users/admin_users_page.dart';
import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Storage implements SessionStorage {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Users extends UserAdminService {
  @override
  Future<List<Map<String, dynamic>>> getUsers({String? search, String? estado, String? rol}) async => [
    {'id': 10, 'nombre': 'Usuario de prueba', 'email': 'test@example.invalid',
      'rol': 'USUARIO', 'estado_cuenta': 'ACTIVO', 'is_verified': true},
  ];
}

class _DeferredUsers extends _Users {
  final requests = <Completer<List<Map<String, dynamic>>>>[];
  @override
  Future<List<Map<String, dynamic>>> getUsers({String? search, String? estado, String? rol}) {
    final request = Completer<List<Map<String, dynamic>>>();
    requests.add(request);
    return request.future;
  }
}

class _SavingUsers extends _Users {
  final pendingSave = Completer<Map<String, dynamic>>();
  int saves = 0;
  @override
  Future<Map<String, dynamic>> createUser({required String nombre, required String email,
    String? telefono, required String password, required String rol}) {
    saves++;
    return pendingSave.future;
  }
}

Map<String, dynamic> _user(String name) => {
  'id': 10, 'nombre': name, 'email': 'test@example.invalid',
  'rol': 'USUARIO', 'estado_cuenta': 'ACTIVO', 'is_verified': true,
};

Future<void> _openUserForm(WidgetTester tester, _SavingUsers service) async {
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: AdminUsersPage(service: service)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nuevo usuario'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Prueba temporal');
  await tester.enterText(find.widgetWithText(TextFormField, 'Correo electrónico'), 'test@example.invalid');
  await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'test-only-password');
}

void main() {
  for (final oldFails in [false, true]) {
    testWidgets('carga antigua ${oldFails ? 'fallida' : 'exitosa'} no reemplaza la búsqueda más reciente', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _DeferredUsers();
      await tester.pumpWidget(MaterialApp(home: AdminUsersPage(service: service)));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'resultado nuevo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(service.requests.length, 2);
      service.requests.last.complete([_user('Resultado nuevo')]);
      await tester.pumpAndSettle();
      if (oldFails) {
        service.requests.first.completeError(const UserAdminException('Error de consulta antigua'));
      } else {
        service.requests.first.complete([_user('Resultado antiguo')]);
      }
      await tester.pumpAndSettle();
      expect(find.text('Resultado nuevo'), findsOneWidget);
      expect(find.text('Resultado antiguo'), findsNothing);
      expect(find.text('Error de consulta antigua'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cinco envíos inmediatos crean un solo usuario', (tester) async {
    final service = _SavingUsers();
    await _openUserForm(tester, service);
    final submit = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Crear')).onPressed!;
    for (var i = 0; i < 5; i++) { submit(); }
    await tester.pump();
    expect(service.saves, 1);
    service.pendingSave.complete({'id': 11});
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no cierra el formulario al tocar fuera o pulsar Atrás mientras guarda', (tester) async {
    final service = _SavingUsers();
    await _openUserForm(tester, service);
    await tester.tap(find.text('Crear'));
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AlertDialog), findsOneWidget);
    service.pendingSave.complete({'id': 11});
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controladores se liberan al terminar la transición, no al iniciar el cierre', (tester) async {
    final service = _SavingUsers();
    await _openUserForm(tester, service);
    final controller = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Nombre')).controller!;
    void listener() {}
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    expect(() => controller.addListener(listener), returnsNormally);
    controller.removeListener(listener);
    await tester.pumpAndSettle();
    expect(() => controller.addListener(listener), throwsFlutterError);
    expect(tester.takeException(), isNull);
  });

  test('administración usa API_BASE_URL y cliente autenticado para todo el CRUD', () async {
    final manager = SessionManager(storage: _Storage());
    await manager.establishSession(accessToken: 'test-access', refreshToken: 'test-refresh', role: 'ADMINISTRADOR');
    final paths = <String>[];
    final service = UserAdminService(client: AuthenticatedHttpClient(
      sessionManager: manager,
      client: MockClient((request) async {
        expect(request.url.origin, Uri.parse(ApiConfig.current.baseUrl).origin);
        expect(request.headers['Authorization'], 'Bearer test-access');
        paths.add('${request.method} ${request.url.path}');
        return http.Response(jsonEncode({'ok': true, 'data':
          request.method == 'GET' && request.url.path.endsWith('/users') ? [] : {'id': 10}}), 200);
      }),
    ));
    await service.getUsers();
    await service.getUser(10);
    await service.createUser(nombre: 'Prueba', email: 'test@example.invalid', password: 'test-only', rol: 'USUARIO');
    await service.updateUser(id: 10, nombre: 'Prueba', email: 'test@example.invalid', rol: 'USUARIO');
    await service.setUserStatus(10, 'SUSPENDIDO');
    await service.deleteUser(10);
    expect(paths, ['GET /api/users', 'GET /api/users/10', 'POST /api/users',
      'PUT /api/users/10', 'PATCH /api/users/10/status', 'DELETE /api/users/10']);
  });

  testWidgets('panel de usuarios conserva listado real y funciona a 320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: AdminUsersPage(service: _Users())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Usuario de prueba'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Usuario de prueba'), findsOneWidget);
    expect(find.text('test@example.invalid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
