import 'dart:convert';
import 'package:animap/features/admin/data/reports/admin_reports_service.dart';
import 'package:animap/features/admin/presentation/pages/bitacora/admin_bitacora_page.dart';
import 'package:animap/features/admin/presentation/pages/reports/admin_reports_page.dart';
import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/report/data/mascotas_perdidas_service.dart';
import 'package:animap/features/report/presentation/pages/report_type_selector_page.dart';
import 'package:animap/features/report/presentation/pages/report_search_page.dart';
import 'package:animap/features/sighting/presentation/pages/create_sighting_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryStore implements SessionStorage {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

Map<String, dynamic> publicReport({
  String id = 'lost_71',
  String name = 'Mora',
  String type = 'lost',
}) => {
  'id': id,
  'petName': name,
  'details': 'Perro · Criolla · Café',
  'location': 'Punto marcado en el mapa',
  'reference': 'Frente al parque',
  'description': 'Descripción QA',
  'dateText': '2026-11-01T03:00:00Z',
  'imageUrl': null,
  'imageUrls': <String>[],
  'type': type,
  'lat': 4.65,
  'lng': -74.11,
  'isOwner': false,
};
Future<AuthenticatedHttpClient> authorizedClient(
  Future<http.Response> Function(http.Request) respond,
) async {
  final manager = SessionManager(storage: MemoryStore());
  await manager.establishSession(
    accessToken: 'test-admin',
    refreshToken: 'test-refresh',
    role: 'ADMINISTRADOR',
  );
  return AuthenticatedHttpClient(
    sessionManager: manager,
    client: MockClient(respond),
  );
}

void main() {
  test(
    'catálogo usa la API pública compartida y normaliza fechas a Bogotá',
    () async {
      final service = MascotasPerdidasService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/map/reports');
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': [publicReport()],
            }),
            200,
          );
        }),
      );
      final reports = await service.obtenerReportes();
      service.dispose();
      expect(reports.single.id, 'lost_71');
      expect(reports.single.fecha!.day, 31);
      expect(reports.single.fecha!.month, 10);
      expect(reports.single.fecha!.hour, 22);
    },
  );
  testWidgets(
    'selector conserva ambas creaciones y añade acceso separado a búsqueda',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const ReportTypeSelectorPage(),
          routes: {
            '/search-reports': (_) =>
                ReportarBuscarPage(reportsLoader: () async => []),
          },
        ),
      );
      expect(find.byKey(const ValueKey('report-lost-pet')), findsOneWidget);
      expect(find.byKey(const ValueKey('report-sighting')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('search-public-reports')),
      );
      await tester.tap(find.byKey(const ValueKey('search-public-reports')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportarBuscarPage), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ReportTypeSelectorPage), findsOneWidget);
    },
  );
  testWidgets('búsqueda comparte reportes y separa pérdidas de avistamientos', (
    tester,
  ) async {
    final data = [
      MascotaReporte.fromJson(publicReport()),
      MascotaReporte.fromJson(
        publicReport(id: 'sighting_81', name: 'Vista', type: 'sighting'),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: ReportarBuscarPage(reportsLoader: () async => data)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mora'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mora'), findsOneWidget);
    expect(find.text('Vista'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Avistamientos'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Avistamientos'));
    await tester.tap(find.text('Avistamientos'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Vista'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Vista'), findsOneWidget);
    expect(find.text('Mora'), findsNothing);
  });
  testWidgets('búsqueda a 320px informa vacío sin overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ReportarBuscarPage(reportsLoader: () async => [])),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('No hay mascotas perdidas para mostrar.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'búsqueda seleccionada abre avistamiento vinculado al reportId correcto',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CreateSightingPage(
            reporteInicialId: 71,
            reportsLoader: () async => [
              {
                'id': 71,
                'mascota': {
                  'nombre': 'Mora',
                  'especie': 'Perro',
                  'raza': 'Criolla',
                  'fotoPrincipal': null,
                },
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final option = find.byKey(const ValueKey('linkable-report-71'));
      expect(option, findsOneWidget);
      expect(
        find.descendant(of: option, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('administración consulta la ruta canónica con Bearer vigente', (
    tester,
  ) async {
    final client = await authorizedClient((request) async {
      expect(request.url.path, '/api/admin/reports');
      expect(request.headers['Authorization'], 'Bearer test-admin');
      return http.Response(
        jsonEncode({'ok': true, 'reports': <Object>[]}),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdminReportsPage(service: AdminReportsService(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('bitácora usa cliente autenticado y muestra sus registros', (
    tester,
  ) async {
    final client = await authorizedClient((request) async {
      expect(request.url.path, '/api/admin/bitacora');
      expect(request.headers['Authorization'], 'Bearer test-admin');
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': [
            {
              'id': 1,
              'fk_admin': 2,
              'administrador': 'admin@example.invalid',
              'modulo': 'REPORTES',
              'accion': 'EDITAR',
              'entidad_afectada': 'reporte',
              'id_entidad_afectada': 71,
              'fecha_hora': '2026-11-01T12:00:00Z',
            },
          ],
          'paginacion': {'totalPaginas': 1},
        }),
        200,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdminBitacoraPage(
          baseUrl: 'http://10.0.2.2:3000/api',
          token: 'unused-snapshot',
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Administrador: admin@example.invalid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reporte propio permanece visible sin ofrecer vincular avistamiento',
    (tester) async {
      final own = publicReport()..['isOwner'] = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ReportarBuscarPage(
            reportsLoader: () async => [MascotaReporte.fromJson(own)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Mora'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Mora'));
      await tester.pumpAndSettle();
      expect(find.text('Mora'), findsWidgets);
      expect(find.text('Reportar avistamiento de esta mascota'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reporte inicial no disponible no queda seleccionado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reporteInicialId: 71,
          reportsLoader: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('linkable-report-71')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
