import 'dart:async';
import 'dart:convert';

import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:animap/features/report/data/reports_service.dart';
import 'package:animap/features/report/presentation/pages/create_lost_report_page.dart';
import 'package:animap/features/report/presentation/pages/own_report_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> ownReport({String state = 'ACTIVO'}) => {
  'id': 71,
  'mascotaId': 5,
  'estado': state,
  'descripcion': 'Descripción del reporte existente',
  'creadoEn': '2026-10-01T16:00:00Z',
  'cerradoEn': state == 'FINALIZADO' ? '2026-10-02T18:00:00Z' : null,
  'avistamientosCount': 2,
  'mascota': {
    'id': 5,
    'nombre': 'Mora',
    'especie': 'Perro',
    'raza': 'Criolla',
    'estado': state == 'ACTIVO' ? 'PERDIDA' : 'ACTIVA',
    'fotoPrincipal': null,
  },
  'ubicacion': {
    'metodo': 'MAPA',
    'lat': 4.651,
    'lng': -74.109,
    'referencia': 'Frente a la entrada del parque',
    'direccion': 'Frente a la entrada del parque',
  },
};

OwnReportDetails details({String state = 'ACTIVO'}) => OwnReportDetails(
  report: ownReport(state: state),
  pet: {
    'id': 5,
    'color': 'Café',
    'edad_aprox': 2,
    'unidad_edad': 'ANIOS',
    'sexo': 'HEMBRA',
    'observaciones': 'Observaciones propias de la mascota',
  },
  photos: const [],
);

Widget fakeMap(BuildContext context, LatLng position, bool interactive) =>
    Text('${interactive ? 'Mapa completo' : 'Mapa mini'}: $position');

OwnReportDetailPage detailPage({
  OwnReportDetails? data,
  Future<OwnReportDetails> Function(int)? loader,
}) => OwnReportDetailPage(
  reportId: 71,
  loader: loader ?? (_) async => data ?? details(),
  mapBuilder: fakeMap,
  historyBuilder: (id) =>
      Scaffold(appBar: AppBar(), body: Text('Historial $id')),
);

Future<void> openMyReports(
  WidgetTester tester, {
  Widget Function(int)? builder,
  Future<void> Function(int)? closer,
  Future<List<Map<String, dynamic>>> Function()? reportsLoader,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CreateLostReportPage(
        petsLoader: () async => [],
        reportsLoader: reportsLoader ?? () async => [ownReport()],
        reportDetailBuilder: builder ?? (_) => detailPage(),
        reportCloser: closer,
        reportHistoryBuilder: (id) =>
            Scaffold(appBar: AppBar(), body: Text('Historial tarjeta $id')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mis reportes'));
  await tester.pumpAndSettle();
}

class MemoryStorage implements SessionStorage {
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
  testWidgets('una tarjeta de Mis reportes abre el detalle', (tester) async {
    await openMyReports(tester);
    await tester.tap(find.text('Mora'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del reporte'), findsOneWidget);
    expect(find.byType(ReportDetailPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('own-report-card-71')), findsOneWidget);
    expect(find.text('Mora'), findsOneWidget);
    expect(find.text('Encontrada'), findsOneWidget);
  });

  for (final state in ['ACTIVO', 'FINALIZADO']) {
    testWidgets('$state muestra datos privados completos y fechas Bogotá', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: detailPage(data: details(state: state)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(state), findsOneWidget);
      expect(find.text('Mora'), findsOneWidget);
      expect(find.text('Perro · Criolla'), findsOneWidget);
      expect(find.textContaining('01/10/2026, 11:00'), findsOneWidget);
      if (state == 'FINALIZADO') {
        expect(find.textContaining('02/10/2026, 13:00'), findsOneWidget);
      }
      expect(find.text('Descripción del reporte existente'), findsOneWidget);
      expect(find.textContaining('Color: Café'), findsOneWidget);
      expect(find.textContaining('Edad aproximada: 2 años'), findsOneWidget);
      expect(
        find.textContaining('Observaciones de la mascota:'),
        findsOneWidget,
      );
      final view = tester.widget<ReportDetailPage>(
        find.byType(ReportDetailPage),
      );
      expect(view.report.isOwner, isTrue);
      expect(view.report.showContact, isFalse);
      expect(view.report.ownerPhone, isEmpty);
      expect(view.report.ownerEmail, isEmpty);
      expect(
        view.report.type,
        state == 'ACTIVO' ? ReportType.lost : ReportType.found,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-report-location')),
        200,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('open-report-location')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Señas: Frente a la entrada del parque'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('open-report-location')));
      await tester.pumpAndSettle();
      expect(find.byType(ReportLocationViewPage), findsOneWidget);
      expect(find.textContaining('Mapa completo:'), findsOneWidget);
    });
  }

  testWidgets('principal primero, fotos privadas y URLs externas excluidas', (
    tester,
  ) async {
    final data = details();
    await tester.pumpWidget(
      MaterialApp(
        home: detailPage(
          data: OwnReportDetails(
            report: data.report,
            pet: data.pet,
            photos: [
              {'url': '/api/pets/images/second', 'esPrincipal': false},
              {'url': '/api/pets/images/main', 'esPrincipal': true},
              {'url': 'https://foreign.invalid/api/pets/images/secret'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final report = tester
        .widget<ReportDetailPage>(find.byType(ReportDetailPage))
        .report;
    expect(report.imageUrls.map((url) => Uri.parse(url).path), [
      '/api/pets/images/main',
      '/api/pets/images/second',
    ]);
    expect(report.imageUrl, report.imageUrls.first);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-report-gallery')),
      250,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('open-report-gallery')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-report-gallery')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReportPhotoGalleryPage>(find.byType(ReportPhotoGalleryPage))
          .photos,
      report.imageUrls,
    );
  });

  testWidgets('sin fotos no inventa imágenes y conserva acceso al historial', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: detailPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-sightings-71')),
      200,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('open-sightings-71')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-sightings-71')));
    await tester.pumpAndSettle();
    expect(find.text('Historial 71'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Esta mascota no tiene fotos disponibles.'),
      200,
    );
    expect(find.byKey(const ValueKey('open-report-gallery')), findsNothing);
  });

  for (final method in ['GPS', 'DIRECCION']) {
    testWidgets('$method conserva las coordenadas y la ubicación legible', (
      tester,
    ) async {
      final data = details();
      data.report['ubicacion'] = {
        'metodo': method,
        'lat': 4.651,
        'lng': -74.109,
        'direccion': method == 'DIRECCION'
            ? 'Dirección validada del evento'
            : null,
        'referencia': method == 'GPS' ? 'Señas del evento' : null,
      };
      await tester.pumpWidget(MaterialApp(home: detailPage(data: data)));
      await tester.pumpAndSettle();
      final report = tester
          .widget<ReportDetailPage>(find.byType(ReportDetailPage))
          .report;
      expect(report.position, const LatLng(4.651, -74.109));
      expect(
        report.location,
        method == 'DIRECCION'
            ? 'Dirección validada del evento'
            : 'Punto marcado en el mapa',
      );
      expect(report.reference, method == 'GPS' ? 'Señas del evento' : '');
    });
  }

  testWidgets('Editar no abre detalle ni pierde descripción o señas', (
    tester,
  ) async {
    var opened = 0;
    await openMyReports(
      tester,
      builder: (_) {
        opened++;
        return detailPage();
      },
    );
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.text('Descripción del reporte existente'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('lost-report-reference')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Frente a la entrada del parque'), findsOneWidget);
  });

  testWidgets('Encontrada conserva confirmación y cierre sin abrir detalle', (
    tester,
  ) async {
    var opened = 0;
    var closed = 0;
    await openMyReports(
      tester,
      builder: (_) {
        opened++;
        return detailPage();
      },
      closer: (id) async {
        expect(id, 71);
        closed++;
      },
    );
    await tester.tap(find.text('Encontrada'));
    await tester.pumpAndSettle();
    expect(find.text('Finalizar reporte'), findsOneWidget);
    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(opened, 0);
    expect(find.byKey(const ValueKey('own-report-card-71')), findsOneWidget);
  });

  testWidgets('historial de la tarjeta no activa su onTap', (tester) async {
    var opened = 0;
    await openMyReports(
      tester,
      builder: (_) {
        opened++;
        return detailPage();
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-sightings-71')));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.text('Historial tarjeta 71'), findsOneWidget);
  });

  testWidgets('error de API permite reintentar sin mostrar datos previos', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: detailPage(
          loader: (_) async {
            if (++calls == 1) throw ReportsException('Reporte no encontrado.');
            return details();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reporte no encontrado.'), findsOneWidget);
    expect(find.byType(ReportDetailPage), findsNothing);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(ReportDetailPage), findsOneWidget);
  });

  testWidgets('respuesta vacía o ubicación inválida no inventa un reporte', (
    tester,
  ) async {
    for (final data in [
      const OwnReportDetails(report: {}, pet: {}, photos: []),
      OwnReportDetails(
        report: {
          ...ownReport(),
          'ubicacion': {'lat': null, 'lng': null},
        },
        pet: {},
        photos: [],
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: OwnReportDetailPage(
            key: UniqueKey(),
            reportId: 71,
            loader: (_) async => data,
            mapBuilder: fakeMap,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReportDetailPage), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cambio de reporte y desmontaje ignoran cargas antiguas', (
    tester,
  ) async {
    final pending = Completer<OwnReportDetails>();
    await tester.pumpWidget(
      MaterialApp(
        home: OwnReportDetailPage(
          reportId: 71,
          loader: (_) => pending.future,
          mapBuilder: fakeMap,
        ),
      ),
    );
    final second = details(state: 'FINALIZADO');
    await tester.pumpWidget(
      MaterialApp(
        home: OwnReportDetailPage(
          reportId: 72,
          loader: (_) async => OwnReportDetails(
            report: {...second.report, 'id': 72},
            pet: second.pet,
            photos: [],
          ),
          mapBuilder: fakeMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
    pending.complete(details());
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReportDetailPage>(find.byType(ReportDetailPage)).report.id,
      'lost_72',
    );
    final disposed = Completer<OwnReportDetails>();
    await tester.pumpWidget(
      MaterialApp(home: detailPage(loader: (_) => disposed.future)),
    );
    await tester.pumpWidget(const SizedBox());
    disposed.complete(details());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('la carga detenida termina con error recuperable', (
    tester,
  ) async {
    final pending = Completer<OwnReportDetails>();
    await tester.pumpWidget(
      MaterialApp(home: detailPage(loader: (_) => pending.future)),
    );
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);
    pending.complete(details());
    await tester.pumpAndSettle();
    expect(find.byType(ReportDetailPage), findsNothing);
  });

  testWidgets('detalle a 320 px con texto grande no presenta overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = details();
    final report = data.report;
    (report['mascota'] as Map)['nombre'] =
        'Nombre muy largo de una mascota de prueba';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: detailPage(data: data),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Este reporte es tuyo'), 200);
    expect(tester.takeException(), isNull);
  });

  group('consulta privada existente', () {
    late SessionManager session;
    setUp(() async {
      session = SessionManager(storage: MemoryStorage());
      await session.establishSession(
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      );
    });
    test('GET por reportId con Bearer y sin userId del cliente', () async {
      final client = AuthenticatedHttpClient(
        sessionManager: session,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/reports/71');
          expect(request.url.query, isEmpty);
          expect(request.headers['Authorization'], 'Bearer test-access');
          return http.Response(
            jsonEncode({'ok': true, 'report': ownReport()}),
            200,
          );
        }),
      );
      expect((await ReportsService.getOwnReport(71, client: client))['id'], 71);
    });
    for (final code in [404, 500]) {
      test('$code no se transforma en reporte vacío exitoso', () async {
        final client = AuthenticatedHttpClient(
          sessionManager: session,
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'ok': false, 'message': 'No disponible'}),
              code,
            ),
          ),
        );
        await expectLater(
          ReportsService.getOwnReport(71, client: client),
          throwsA(isA<ReportsException>()),
        );
      });
    }
    test('sesión revocada se mantiene bajo control de autenticación', () async {
      final client = AuthenticatedHttpClient(
        sessionManager: session,
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'code': 'SESSION_REVOKED'}), 401),
        ),
      );
      await expectLater(
        ReportsService.getOwnReport(71, client: client),
        throwsA(isA<SessionInvalidException>()),
      );
    });
    for (final body in <Map<String, dynamic>>[
      {'ok': true},
      {'ok': true, 'report': {}},
      {
        'ok': true,
        'report': {...ownReport(), 'id': 99},
      },
    ]) {
      test(
        'rechaza respuesta incompleta o de otro reporte: ${body['report']?['id']}',
        () async {
          final client = AuthenticatedHttpClient(
            sessionManager: session,
            client: MockClient(
              (_) async => http.Response(jsonEncode(body), 200),
            ),
          );
          await expectLater(
            ReportsService.getOwnReport(71, client: client),
            throwsA(isA<ReportsException>()),
          );
        },
      );
    }
  });

  test('autoriza reporte antes de consultar mascota y fotos', () async {
    var reads = 0;
    await expectLater(
      ReportsService.getOwnReportDetails(
        71,
        reportLoader: (_) async => throw ReportsException('No encontrado'),
        petLoader: (_) async {
          reads++;
          return {};
        },
        photosLoader: (_) async {
          reads++;
          return [];
        },
      ),
      throwsA(isA<ReportsException>()),
    );
    expect(reads, 0);
  });
  test(
    'dos reportes de la misma mascota conservan su ID y descripción',
    () async {
      for (final id in [71, 72]) {
        final data = await ReportsService.getOwnReportDetails(
          id,
          reportLoader: (requested) async => {
            ...ownReport(),
            'id': requested,
            'descripcion': 'Reporte $requested',
          },
          petLoader: (petId) async {
            expect(petId, 5);
            return {'id': 5};
          },
          photosLoader: (petId) async {
            expect(petId, 5);
            return [];
          },
        );
        expect(data.report['id'], id);
        expect(data.report['descripcion'], 'Reporte $id');
      }
    },
  );
  test(
    'histórico con mascota inactiva permanece legible sin fotos borradas',
    () async {
      final report = ownReport(state: 'FINALIZADO');
      (report['mascota'] as Map)['estado'] = 'INACTIVA';
      final data = await ReportsService.getOwnReportDetails(
        71,
        reportLoader: (_) async => report,
        petLoader: (_) async =>
            throw StateError('No consultar mascota inactiva'),
        photosLoader: (_) async =>
            throw StateError('No consultar fotos eliminadas'),
      );
      expect(data.report['estado'], 'FINALIZADO');
      expect(data.photos, isEmpty);
    },
  );
  test('rechaza una mascota distinta de la del reporte', () async {
    await expectLater(
      ReportsService.getOwnReportDetails(
        71,
        reportLoader: (_) async => ownReport(),
        petLoader: (_) async => {'id': 6},
        photosLoader: (_) async => [],
      ),
      throwsA(isA<ReportsException>()),
    );
  });
}
