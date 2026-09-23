import 'dart:async';
import 'dart:convert';

import 'package:animap/features/admin/data/faq/faq_service.dart';
import 'package:animap/features/admin/presentation/pages/faq/admin_faq_page.dart';
import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
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

class _ControlledFaqService extends FaqService {
  final createRequests = <Completer<Map<String, dynamic>>>[];
  final updateRequests = <Completer<Map<String, dynamic>>>[];
  int listCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> getCategories() async => [
    {'id': 1, 'nombre': 'General', 'total_faq': 1},
  ];

  @override
  Future<List<Map<String, dynamic>>> getAdminFaqs() async {
    listCalls++;
    return [
      {
        'id': 1,
        'fk_categoria': 1,
        'categoria': 'General',
        'pregunta': 'Pregunta existente',
        'respuesta': 'Respuesta existente',
        'activa': true,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> createFaq(Map<String, dynamic> input) {
    final request = Completer<Map<String, dynamic>>();
    createRequests.add(request);
    return request.future;
  }

  @override
  Future<Map<String, dynamic>> updateFaq(int id, Map<String, dynamic> input) {
    final request = Completer<Map<String, dynamic>>();
    updateRequests.add(request);
    return request.future;
  }
}

class _PopObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}

Future<void> _openForm(
  WidgetTester tester,
  _ControlledFaqService service, {
  required bool editing,
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AdminFaqPage(service: service),
      navigatorObservers: observer == null ? [] : [observer],
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    editing ? find.byTooltip('Editar FAQ') : find.text('Agregar FAQ'),
  );
  await tester.pumpAndSettle();
  if (!editing) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Pregunta'),
      'Nueva pregunta',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Respuesta'),
      'Nueva respuesta',
    );
  }
}

void main() {
  for (final editing in [false, true]) {
    testWidgets(
      '${editing ? 'editar' : 'crear'}: cinco Guardar producen una petición y un solo pop',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = _ControlledFaqService();
        final observer = _PopObserver();
        await _openForm(tester, service, editing: editing, observer: observer);
        final save = tester.widget<FilledButton>(
          find.byType(FilledButton).last,
        );
        for (var index = 0; index < 5; index++) {
          save.onPressed!();
        }
        await tester.pump();
        final requests = editing
            ? service.updateRequests
            : service.createRequests;
        expect(requests.length, 1);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
          isNull,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(observer.pops, 0);

        requests.single.complete({'id': editing ? 1 : 2});
        await tester.pumpAndSettle();
        expect(observer.pops, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(AdminFaqPage), findsOneWidget);
        expect(service.listCalls, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('409 deja el formulario abierto y permite reintentar', (
    tester,
  ) async {
    final service = _ControlledFaqService();
    final observer = _PopObserver();
    await _openForm(tester, service, editing: false, observer: observer);
    tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed!();
    await tester.pump();
    service.createRequests.single.completeError(
      const FaqException(
        'Ya existe una pregunta frecuente igual en esta categoría.',
      ),
    );
    await tester.pumpAndSettle();
    expect(observer.pops, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Ya existe una pregunta frecuente igual en esta categoría.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNotNull,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Pregunta'),
      'Otra pregunta',
    );
    tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed!();
    await tester.pump();
    expect(service.createRequests.length, 2);
    service.createRequests.last.complete({'id': 2});
    await tester.pumpAndSettle();
    expect(observer.pops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fallo al editar habilita Guardar otra vez sin cerrar', (
    tester,
  ) async {
    final service = _ControlledFaqService();
    final observer = _PopObserver();
    await _openForm(tester, service, editing: true, observer: observer);
    tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed!();
    await tester.pump();
    service.updateRequests.single.completeError(Exception('detalle interno'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(observer.pops, 0);
    expect(
      find.text(
        'No pudimos guardar la pregunta frecuente. Intenta nuevamente.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  test('servicio convierte 409 de POST y PUT en mensaje amigable', () async {
    final manager = SessionManager(storage: _MemoryStorage());
    await manager.establishSession(
      accessToken: 'access-test',
      refreshToken: 'refresh-test',
      role: 'ADMINISTRADOR',
    );
    final client = AuthenticatedHttpClient(
      sessionManager: manager,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': false,
            'code': 'FAQ_DUPLICATE',
            'message': 'detalle técnico oculto',
          }),
          409,
        ),
      ),
    );
    final service = FaqService(client: client);
    final input = {
      'categoriaId': 1,
      'pregunta': 'Pregunta',
      'respuesta': 'Respuesta',
      'activa': true,
    };
    for (final send in <Future<Map<String, dynamic>> Function()>[
      () => service.createFaq(input),
      () => service.updateFaq(1, input),
    ]) {
      await expectLater(
        send(),
        throwsA(
          isA<FaqException>().having(
            (error) => error.message,
            'mensaje',
            'Ya existe una pregunta frecuente igual en esta categoría.',
          ),
        ),
      );
    }
  });
}
