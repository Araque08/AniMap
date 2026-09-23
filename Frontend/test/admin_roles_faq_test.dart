import 'dart:async';
import 'dart:convert';

import 'package:animap/features/admin/data/faq/faq_service.dart';
import 'package:animap/features/admin/presentation/pages/faq/admin_faq_page.dart';
import 'package:animap/features/admin/presentation/pages/faq/admin_faq_categories_page.dart';
import 'package:animap/features/admin/presentation/pages/home/admin_home_page.dart';
import 'package:animap/features/auth/data/auth_service.dart';
import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/auth/presentation/pages/login_page.dart';
import 'package:animap/features/auth/presentation/session_gate.dart';
import 'package:animap/features/faq/presentation/screens/faq_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryStorage implements SessionStorage {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FaqFixture extends FaqService {
  bool active = true;
  Map<String, dynamic>? createdFaq;
  Map<String, dynamic>? updatedFaq;
  String? createdCategory;
  String? updatedCategory;
  int? deletedCategory;
  @override
  Future<List<Map<String, dynamic>>> getCategories() async => [
    {'id': 1, 'nombre': 'General', 'total_faq': 1},
    if (createdCategory != null)
      {'id': 2, 'nombre': updatedCategory ?? createdCategory, 'total_faq': 0},
  ];
  @override
  Future<List<Map<String, dynamic>>> getPublicFaqs({
    int? categoriaId,
    String? search,
  }) async => [
    {
      'id': 1,
      'categoria': 'General',
      'pregunta': 'FAQ real',
      'respuesta': 'Respuesta real',
      'activa': true,
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> getAdminFaqs() async => [
    {
      'id': 1,
      'fk_categoria': 1,
      'categoria': 'General',
      'pregunta': 'FAQ real',
      'respuesta': 'Respuesta real',
      'activa': active,
    },
  ];
  @override
  Future<Map<String, dynamic>> setFaqStatus(int id, bool next) async {
    active = next;
    return {'id': id, 'activa': active};
  }

  @override
  Future<Map<String, dynamic>> createFaq(Map<String, dynamic> input) async {
    createdFaq = input;
    return {'id': 2, ...input};
  }

  @override
  Future<Map<String, dynamic>> updateFaq(
    int id,
    Map<String, dynamic> input,
  ) async {
    updatedFaq = input;
    return {'id': id, ...input};
  }

  @override
  Future<Map<String, dynamic>> createCategory(
    String name,
    String? description,
  ) async {
    createdCategory = name;
    return {'id': 2, 'nombre': name};
  }

  @override
  Future<Map<String, dynamic>> updateCategory(
    int id,
    String name,
    String? description,
  ) async {
    updatedCategory = name;
    return {'id': id, 'nombre': name};
  }

  @override
  Future<void> deleteCategory(int id) async {
    deletedCategory = id;
  }
}

class _DeletableFaqFixture extends FaqService {
  final entries = <Map<String, dynamic>>[
    {
      'id': 1,
      'fk_categoria': 10,
      'categoria': 'Cuenta y acceso',
      'pregunta': 'FAQ A',
      'respuesta': 'A',
      'activa': true,
    },
    {
      'id': 2,
      'fk_categoria': 10,
      'categoria': 'Cuenta y acceso',
      'pregunta': 'FAQ B',
      'respuesta': 'B',
      'activa': false,
    },
    {
      'id': 3,
      'fk_categoria': 10,
      'categoria': 'Cuenta y acceso',
      'pregunta': 'FAQ C',
      'respuesta': 'C',
      'activa': true,
    },
  ];
  int deleteCalls = 0;
  Completer<void>? pauseDelete;
  bool failDelete = false;

  @override
  Future<List<Map<String, dynamic>>> getCategories() async => [
    {'id': 10, 'nombre': 'Cuenta y acceso', 'total_faq': entries.length},
  ];
  @override
  Future<List<Map<String, dynamic>>> getAdminFaqs() async =>
      entries.map((entry) => {...entry}).toList();
  @override
  Future<List<Map<String, dynamic>>> getPublicFaqs({
    int? categoriaId,
    String? search,
  }) async => entries
      .where((entry) => entry['activa'] == true)
      .map((entry) => {...entry})
      .toList();
  @override
  Future<void> deleteFaq(int id) async {
    deleteCalls += 1;
    await pauseDelete?.future;
    if (failDelete) {
      throw const FaqException(
        'No pudimos eliminar la pregunta frecuente. Intenta nuevamente.',
      );
    }
    entries.removeWhere((entry) => entry['id'] == id);
  }
}

void main() {
  for (final role in ['USUARIO', 'ADMINISTRADOR']) {
    testWidgets('Login $role dirige al destino correcto y guarda rol', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final manager = SessionManager(storage: _MemoryStorage());
      final service = AuthService(
        sessionManager: manager,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'accessToken': 'access',
                'refreshToken': 'refresh',
                'user': {'nombre': 'Prueba', 'rol': role},
              },
            }),
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(authService: service),
          routes: {
            '/home': (_) => const Scaffold(body: Text('AniMap usuario')),
            '/admin': (_) => const Scaffold(body: Text('AniMap admin')),
          },
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo electrónico'),
        'test@example.invalid',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'ClavePrueba',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar Sesión'));
      await tester.pumpAndSettle();
      expect(manager.role, role);
      expect(
        find.text(role == 'ADMINISTRADOR' ? 'AniMap admin' : 'AniMap usuario'),
        findsOneWidget,
      );
    });
  }

  testWidgets('rol inválido no entra a ningún panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = SessionManager(storage: _MemoryStorage());
    final service = AuthService(
      sessionManager: manager,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'accessToken': 'access',
              'refreshToken': 'refresh',
              'user': {'rol': 'OTRO'},
            },
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: LoginPage(authService: service)));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo electrónico'),
      'test@example.invalid',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña'),
      'ClavePrueba',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar Sesión'));
    await tester.pumpAndSettle();
    expect(
      find.text('La cuenta no tiene un rol válido asignado'),
      findsOneWidget,
    );
    expect(manager.isAuthenticated, false);
  });

  testWidgets('refresh restaura panel ADMINISTRADOR y logout limpia rol', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _MemoryStorage()
      ..values[SessionManager.refreshTokenKey] = 'refresh-a';
    final manager = SessionManager(
      storage: storage,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          return http.Response('{"ok":true}', 200);
        }
        return http.Response(
          '{"ok":true,"data":{"accessToken":"access-b","refreshToken":"refresh-b","role":"ADMINISTRADOR"}}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(sessionManager: manager),
        routes: {'/login': (_) => const Scaffold(body: Text('Login destino'))},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.text('Preguntas frecuentes'), findsOneWidget);
    expect(find.text('Categorías FAQ'), findsOneWidget);
    expect(find.text('Moderar contenido'), findsNothing);
    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión').last);
    await tester.pumpAndSettle();
    expect(find.text('Login destino'), findsOneWidget);
    expect(manager.role, isNull);
    expect(await storage.read(SessionManager.refreshTokenKey), isNull);
  });

  testWidgets(
    'FAQ pública presenta datos recibidos del servicio, no estáticos',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: FaqScreen(faqService: _FaqFixture())),
      );
      await tester.pumpAndSettle();
      expect(find.text('FAQ real'), findsOneWidget);
      expect(find.text('¿Qué es AniMap?'), findsNothing);
    },
  );

  testWidgets('FAQ activa, archivada y reactivada conserva acciones y estilo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FaqFixture();
    final editButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Editar FAQ',
    );
    final activateButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Activar FAQ',
    );
    await tester.pumpWidget(MaterialApp(home: AdminFaqPage(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('FAQ real'), findsOneWidget);
    expect(tester.widget<Card>(find.byType(Card)).color, Colors.white);
    expect(tester.widget<Text>(find.text('FAQ real')).style?.color, isNull);
    expect(find.textContaining('Activa'), findsOneWidget);
    expect(find.byKey(const ValueKey('archived-faq-indicator')), findsNothing);
    expect(find.byKey(const ValueKey('archived-faq-badge')), findsNothing);
    expect(tester.widget<IconButton>(editButton).onPressed, isNotNull);
    expect(find.byTooltip('Eliminar FAQ'), findsOneWidget);
    await tester.tap(find.byTooltip('Archivar FAQ'));
    await tester.pumpAndSettle();
    expect(service.active, false);
    expect(find.text('ARCHIVADA'), findsOneWidget);
    expect(find.byTooltip('Eliminar FAQ'), findsOneWidget);
    expect(
      tester.widget<Card>(find.byType(Card)).color,
      const Color(0xFFECEFF1),
    );
    final indicator = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('archived-faq-indicator')),
    );
    final border = (indicator.decoration as BoxDecoration).border as Border;
    expect(border.left.width, 4);
    expect(border.left.color, const Color(0xFF90A4AE));
    final badge = tester.widget<Container>(
      find.byKey(const ValueKey('archived-faq-badge')),
    );
    expect((badge.decoration as BoxDecoration).color, const Color(0xFFCFD8DC));
    expect(
      tester.widget<Text>(find.text('FAQ real')).style?.color,
      const Color(0xFF596168),
    );
    expect(
      tester.widget<Text>(find.text('General')).style?.color,
      const Color(0xFF6C7478),
    );
    final edit = tester.widget<IconButton>(editButton);
    final activate = tester.widget<IconButton>(activateButton);
    expect(edit.onPressed, isNotNull);
    expect(activate.onPressed, isNotNull);
    expect(
      edit.icon,
      isA<Icon>().having(
        (icon) => icon.color,
        'color',
        const Color(0xFF7B8387),
      ),
    );
    expect(
      activate.icon,
      isA<Icon>().having(
        (icon) => icon.color,
        'color',
        const Color(0xFF2E7D5B),
      ),
    );
    await tester.tap(find.byTooltip('Editar FAQ'));
    await tester.pumpAndSettle();
    expect(find.text('Editar FAQ'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Activar FAQ'));
    await tester.pumpAndSettle();
    expect(service.active, true);
    expect(tester.widget<Card>(find.byType(Card)).color, Colors.white);
    expect(tester.widget<Text>(find.text('FAQ real')).style?.color, isNull);
    expect(find.textContaining('Activa'), findsOneWidget);
    expect(find.byKey(const ValueKey('archived-faq-indicator')), findsNothing);
    expect(find.byKey(const ValueKey('archived-faq-badge')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'administración crea y edita FAQ sin excepción al cerrar diálogos',
    (tester) async {
      final service = _FaqFixture();
      await tester.pumpWidget(
        MaterialApp(home: AdminFaqPage(service: service)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar FAQ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Pregunta'),
        'Nueva pregunta',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Respuesta'),
        'Nueva respuesta',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(service.createdFaq?['pregunta'], 'Nueva pregunta');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Editar FAQ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Pregunta'),
        'Pregunta editada',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(service.updatedFaq?['pregunta'], 'Pregunta editada');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'administración de categorías crea, edita y bloquea eliminar una en uso',
    (tester) async {
      final service = _FaqFixture();
      await tester.pumpWidget(
        MaterialApp(home: AdminFaqCategoriesPage(service: service)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eliminar categoría').first);
      await tester.pumpAndSettle();
      expect(service.deletedCategory, isNull);
      await tester.tap(find.text('Agregar categoría'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Nueva categoría',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(service.createdCategory, 'Nueva categoría');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Editar categoría').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Categoría editada',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(service.updatedCategory, 'Categoría editada');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eliminar FAQ activa o archivada requiere confirmar y actualiza la lista',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _DeletableFaqFixture();
      await tester.pumpWidget(
        MaterialApp(home: AdminFaqPage(service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Eliminar FAQ'), findsNWidgets(3));
      expect(find.text('ARCHIVADA'), findsOneWidget);

      await tester.tap(find.byTooltip('Eliminar FAQ').first);
      await tester.pumpAndSettle();
      expect(find.text('Eliminar pregunta frecuente'), findsOneWidget);
      expect(
        find.text(
          '¿Seguro que deseas eliminar esta pregunta frecuente? Esta acción no se puede deshacer.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(service.deleteCalls, 0);
      expect(find.text('FAQ A'), findsOneWidget);

      service.pauseDelete = Completer<void>();
      await tester.tap(find.byTooltip('Eliminar FAQ').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pump();
      expect(service.deleteCalls, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      expect(service.deleteCalls, 1);
      service.pauseDelete!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('FAQ B'), findsNothing);
      expect(find.text('ARCHIVADA'), findsNothing);
      expect(find.text('FAQ A'), findsOneWidget);
      expect(find.text('FAQ C'), findsOneWidget);
      expect(
        find.text('Pregunta frecuente eliminada correctamente'),
        findsOneWidget,
      );
      expect(service.entries.length, 2);

      service.pauseDelete = null;
      await tester.tap(find.byTooltip('Eliminar FAQ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('FAQ A'), findsNothing);
      expect(find.text('FAQ C'), findsOneWidget);
      expect(service.deleteCalls, 2);
      expect(
        (await service.getCategories()).single['nombre'],
        'Cuenta y acceso',
      );
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(1080, 800));
      await tester.pumpWidget(
        MaterialApp(home: FaqScreen(faqService: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('FAQ A'), findsNothing);
      expect(find.text('FAQ B'), findsNothing);
      expect(find.text('FAQ C'), findsOneWidget);
    },
  );

  testWidgets('error al eliminar mantiene FAQ y muestra mensaje controlado', (
    tester,
  ) async {
    final service = _DeletableFaqFixture()..failDelete = true;
    await tester.pumpWidget(MaterialApp(home: AdminFaqPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar FAQ').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No pudimos eliminar la pregunta frecuente. Intenta nuevamente.',
      ),
      findsOneWidget,
    );
    expect(find.text('FAQ A'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(service.entries.length, 3);
  });

  test(
    'deleteFaq usa cliente autenticado y traduce 401/403/404/500/red',
    () async {
      Future<FaqService> serviceWith(MockClient mock) async {
        final manager = SessionManager(storage: _MemoryStorage());
        await manager.establishSession(
          accessToken: 'access-test',
          refreshToken: 'refresh-test',
          role: 'ADMINISTRADOR',
        );
        return FaqService(
          client: AuthenticatedHttpClient(
            sessionManager: manager,
            client: mock,
          ),
        );
      }

      http.Request? sent;
      final success = await serviceWith(
        MockClient((request) async {
          sent = request;
          return http.Response(
            '{"ok":true,"data":{"deleted":true,"id":4}}',
            200,
          );
        }),
      );
      await success.deleteFaq(4);
      expect(sent?.method, 'DELETE');
      expect(sent?.url.toString(), 'http://10.0.2.2:3000/api/faqs/4');
      expect(sent?.headers['authorization'], 'Bearer access-test');

      for (final entry in <(int, String, String)>[
        (401, 'NOT_AUTHORIZED', 'Tu sesión expiró'),
        (403, 'ROLE_FORBIDDEN', 'No tienes permiso'),
        (404, 'FAQ_NOT_FOUND', 'ya no existe'),
        (500, 'SERVER_ERROR', 'No pudimos eliminar'),
      ]) {
        final service = await serviceWith(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'ok': false,
                'code': entry.$2,
                'message': 'detalle técnico interno',
              }),
              entry.$1,
            ),
          ),
        );
        await expectLater(
          service.deleteFaq(4),
          throwsA(
            isA<FaqException>().having(
              (error) => error.message,
              'mensaje',
              contains(entry.$3),
            ),
          ),
        );
      }
      final offline = await serviceWith(
        MockClient((_) async => throw http.ClientException('conexión privada')),
      );
      await expectLater(
        offline.deleteFaq(4),
        throwsA(
          isA<FaqException>().having(
            (error) => error.message,
            'mensaje',
            allOf(contains('Revisa tu conexión'), isNot(contains('privada'))),
          ),
        ),
      );
    },
  );
}
