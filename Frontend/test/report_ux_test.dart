import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:animap/features/report/data/device_location_service.dart';
import 'package:animap/features/report/presentation/pages/create_lost_report_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Map<String, dynamic> pet({
  required int id,
  required String name,
  required bool activeReport,
}) => {
  'id': id,
  'nombre': name,
  'especie': 'Especie con un nombre deliberadamente muy extenso',
  'raza': 'Raza con una denominación extraordinariamente larga',
  'estado': activeReport ? 'PERDIDA' : 'ACTIVA',
  'tieneReporteActivo': activeReport,
  'fotoPrincipal': null,
};

MapReport report({
  required String id,
  required LatLng position,
  required String date,
  ReportType type = ReportType.lost,
}) => MapReport(
  id: id,
  title: 'Reporte',
  petName: 'Temporal',
  details: 'Perro',
  location: 'Punto seleccionado',
  reference: '',
  description: 'Temporal',
  dateText: date,
  occurredAt: DateTime.parse(date),
  imageUrl: null,
  position: position,
  type: type,
  showContact: false,
  isOwner: false,
  ownerName: '',
  ownerPhone: '',
  ownerEmail: '',
);

void main() {
  testWidgets('el aviso de 30 días aparece solo en Encontrados sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapReportFilterBar(
            selectedFilter: MapFilter.active,
            onActiveTap: () {},
            onFoundTap: () {},
          ),
        ),
      ),
    );
    expect(
      find.text('Mascotas encontradas en los últimos 30 días'),
      findsNothing,
    );
    final activeHeight = tester
        .getSize(find.byKey(const ValueKey('map-report-filter-bar')))
        .height;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapReportFilterBar(
            selectedFilter: MapFilter.found,
            onActiveTap: () {},
            onFoundTap: () {},
          ),
        ),
      ),
    );
    expect(
      find.text('Mascotas encontradas en los últimos 30 días'),
      findsOneWidget,
    );
    final foundHeight = tester
        .getSize(find.byKey(const ValueKey('map-report-filter-bar')))
        .height;
    expect(foundHeight - activeHeight, lessThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('oculta el formulario cuando todas las mascotas tienen reporte', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateLostReportPage(
          petsLoader: () async => [
            pet(id: 1, name: 'Luna', activeReport: true),
          ],
          reportsLoader: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No tienes mascotas disponibles para reportar.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Luna · Especie con un nombre deliberadamente muy extenso · Raza con una denominación extraordinariamente larga',
      ),
      findsOneWidget,
    );
    expect(find.text('Ver mis reportes'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('solo permite elegir mascotas disponibles sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CreateLostReportPage(
          petsLoader: () async => [
            pet(
              id: 1,
              name: 'Mascota no disponible de nombre larguísimo',
              activeReport: true,
            ),
            pet(
              id: 2,
              name: 'Mascota disponible de nombre larguísimo',
              activeReport: false,
            ),
          ],
          reportsLoader: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.textContaining('Mascota disponible'), findsWidgets);
    expect(find.textContaining('Mascota no disponible'), findsNothing);
    expect(find.textContaining('Estado:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('elige el activo y encontrado más cercano', () {
    const user = LatLng(4.65, -74.10);
    final active = [
      report(
        id: 'lost_1',
        position: const LatLng(4.8, -74.2),
        date: '2026-09-12T10:00:00-05:00',
      ),
      report(
        id: 'lost_2',
        position: const LatLng(4.651, -74.101),
        date: '2026-09-12T09:00:00-05:00',
      ),
    ];
    final found = [
      report(
        id: 'found_1',
        position: const LatLng(4.7, -74.15),
        date: '2026-09-12T12:00:00-05:00',
        type: ReportType.found,
      ),
      report(
        id: 'found_2',
        position: const LatLng(4.6505, -74.1005),
        date: '2026-09-12T11:00:00-05:00',
        type: ReportType.found,
      ),
    ];
    expect(selectNearestReport(active, user)?.id, 'lost_2');
    expect(selectNearestReport(found, user)?.id, 'found_2');
  });

  test('conserva coordenadas duplicadas y desempata por fecha e ID', () {
    const point = LatLng(4.65, -74.10);
    final reports = [
      report(id: 'lost_3', position: point, date: '2026-09-12T10:00:00-05:00'),
      report(id: 'lost_2', position: point, date: '2026-09-12T11:00:00-05:00'),
      report(id: 'lost_1', position: point, date: '2026-09-12T11:00:00-05:00'),
    ];
    expect(reports.length, 3);
    expect(selectNearestReport(reports, point)?.id, 'lost_1');
  });

  test('sin GPS usa fecha e ID como fallback determinista', () {
    final reports = [
      report(
        id: 'lost_2',
        position: const LatLng(4.8, -74.2),
        date: '2026-09-12T10:00:00-05:00',
      ),
      report(
        id: 'lost_1',
        position: const LatLng(4.9, -74.3),
        date: '2026-09-12T11:00:00-05:00',
      ),
    ];
    expect(selectNearestReport(reports, null)?.id, 'lost_1');
  });

  test(
    'el cargador de ubicación puede fallar sin alterar el algoritmo fallback',
    () async {
      Future<DeviceLocation> denied() =>
          Future.error(DeviceLocationException('Permiso denegado'));
      await expectLater(denied(), throwsA(isA<DeviceLocationException>()));
      expect(
        selectNearestReport([
          report(
            id: 'lost_1',
            position: const LatLng(4.65, -74.10),
            date: '2026-09-12T11:00:00-05:00',
          ),
        ], null)?.id,
        'lost_1',
      );
    },
  );
}
