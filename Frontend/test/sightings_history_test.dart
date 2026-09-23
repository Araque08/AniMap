import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:animap/features/sighting/presentation/pages/sightings_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Map<String, dynamic> sighting({
  int id = 91,
  String description = 'Visto junto al parque',
  String date = '2026-09-13T17:00:00.000Z',
  Map<String, dynamic>? photo,
  double lat = 4.657,
  double lng = -74.109,
}) => {
  'id': id,
  'descripcion': description,
  'fechaHora': date,
  'ubicacion': {'metodo': 'GPS', 'lat': lat, 'lng': lng, 'precisionM': 8},
  'foto': photo,
};

Map<String, dynamic> history({
  int reportId = 51,
  String status = 'ACTIVO',
  int? total,
  List<Map<String, dynamic>>? sightings,
}) {
  final values = sightings ?? [sighting()];
  return {
    'ok': true,
    'report': {
      'id': reportId,
      'estado': status,
      'mascota': {
        'id': 31,
        'nombre': 'Luna',
        'especie': 'Perro',
        'raza': 'Criollo',
      },
      'fotoPrincipal': null,
      'ubicacionPerdida': {
        'metodo': 'MAPA',
        'lat': 4.6569,
        'lng': -74.1095,
        'precisionM': null,
      },
    },
    'period': 'ALL',
    'total': total ?? values.length,
    'filteredTotal': values.length,
    'sightings': values,
  };
}

Widget fakeMap(
  BuildContext context,
  LatLng loss,
  List<Map<String, dynamic>> sightings,
  ValueChanged<Map<String, dynamic>> onTap,
) => ColoredBox(
  key: const ValueKey('fake-history-map'),
  color: Colors.blueGrey,
  child: Text('mapa-${sightings.length}-${loss.latitude}'),
);

Future<void> pumpHistory(
  WidgetTester tester, {
  required Future<Map<String, dynamic>> Function(int, String) loader,
  SightingsHistoryMapBuilder? mapBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SightingsHistoryPage(
        reportId: 51,
        loader: loader,
        mapBuilder: mapBuilder ?? fakeMap,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('19 contador X correcto', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportSightingsSummary(reportId: 51, count: 3, onOpen: () {}),
        ),
      ),
    );
    expect(find.text('Ver avistamientos (3)'), findsOneWidget);
  });

  testWidgets('20 contador pertenece al reporte y no a la mascota', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ReportSightingsSummary(reportId: 51, count: 2, onOpen: () {}),
              ReportSightingsSummary(reportId: 52, count: 5, onOpen: () {}),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('report-sightings-summary-51')), findsOne);
    expect(find.byKey(const ValueKey('report-sightings-summary-52')), findsOne);
    expect(find.text('Ver avistamientos (2)'), findsOne);
    expect(find.text('Ver avistamientos (5)'), findsOne);
  });

  testWidgets('21 historial sin datos muestra estado vacío', (tester) async {
    await pumpHistory(
      tester,
      loader: (_, _) async => history(total: 0, sightings: []),
    );
    expect(find.text('Aún no se han reportado avistamientos.'), findsOneWidget);
    expect(find.byKey(const ValueKey('sightings-history-map')), findsNothing);
  });

  testWidgets('22 lista renderiza fecha, descripción y ubicación correctas', (
    tester,
  ) async {
    await pumpHistory(tester, loader: (_, _) async => history());
    expect(find.text('13/09/2026, 12:00'), findsOneWidget);
    expect(find.text('Visto junto al parque'), findsOneWidget);
    expect(find.textContaining('GPS · 4.657, -74.109'), findsOneWidget);
  });

  testWidgets('23 foto opcional se representa sin bloquear la lista', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      loader: (_, _) async => history(
        sightings: [
          sighting(
            photo: {'id': 'photo-91', 'url': '/api/sightings/images/photo-91'},
          ),
          sighting(id: 92),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('history-photo-91')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-sighting-92')), findsOneWidget);
  });

  testWidgets('24 abre el SightingDetailPage del ID seleccionado', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      loader: (_, _) async => history(
        sightings: [sighting(id: 99, description: 'Avistamiento exacto 99')],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('history-sighting-99')));
    await tester.pumpAndSettle();
    expect(find.byType(SightingDetailPage), findsOneWidget);
    expect(find.text('Avistamiento exacto 99'), findsOneWidget);
  });

  testWidgets('25 alternar a Mapa conserva una sola pantalla', (tester) async {
    await pumpHistory(tester, loader: (_, _) async => history());
    await tester.tap(find.text('Mapa'));
    await tester.pump();
    expect(find.byKey(const ValueKey('sightings-history-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-history-map')), findsOneWidget);
    expect(find.text('Avistamientos'), findsOneWidget);
  });

  test('26 punto original de pérdida usa marcador rojo', () {
    final markers = buildSightingsHistoryMarkers(
      reportId: 51,
      lossPosition: const LatLng(4.65, -74.10),
      sightings: const [],
    );
    final loss = markers.single;
    expect(loss.markerId.value, 'loss_51');
    expect(
      loss.icon.toJson(),
      BitmapDescriptor.defaultMarkerWithHue(historyLossMarkerHue).toJson(),
    );
  });

  test('27 avistamientos usan marcador naranja', () {
    final markers = buildSightingsHistoryMarkers(
      reportId: 51,
      lossPosition: const LatLng(4.65, -74.10),
      sightings: [sighting(id: 91)],
    );
    final marker = markers.firstWhere(
      (item) => item.markerId.value == 'sighting_91',
    );
    expect(
      marker.icon.toJson(),
      BitmapDescriptor.defaultMarkerWithHue(historySightingMarkerHue).toJson(),
    );
  });

  test('28 mismas coordenadas mantienen entidades por ID', () {
    final markers = buildSightingsHistoryMarkers(
      reportId: 51,
      lossPosition: const LatLng(4.65, -74.10),
      sightings: [
        sighting(id: 91, lat: 4.657, lng: -74.109),
        sighting(id: 92, lat: 4.657, lng: -74.109),
      ],
    );
    expect(markers.map((item) => item.markerId.value).toSet(), {
      'loss_51',
      'sighting_91',
      'sighting_92',
    });
  });

  testWidgets('29 lista y mapa reaccionan al mismo filtro', (tester) async {
    final periods = <String>[];
    await pumpHistory(
      tester,
      loader: (_, period) async {
        periods.add(period);
        return history(
          total: 2,
          sightings: period == '7D'
              ? [sighting(id: 97, description: 'Dentro de 7 días')]
              : [sighting(id: 91), sighting(id: 92)],
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('period-7D')));
    await tester.pumpAndSettle();
    expect(periods.last, '7D');
    expect(find.text('Dentro de 7 días'), findsOneWidget);
    await tester.tap(find.text('Mapa'));
    await tester.pump();
    expect(find.textContaining('mapa-1-'), findsOneWidget);
  });

  testWidgets('30 filtro sin resultados muestra mensaje específico', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      loader: (_, period) async =>
          period == '30D' ? history(total: 1, sightings: []) : history(),
    );
    await tester.tap(find.byKey(const ValueKey('period-30D')));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay avistamientos para este período.'),
      findsOneWidget,
    );
  });

  testWidgets('31 volver a Todos restaura el historial', (tester) async {
    await pumpHistory(
      tester,
      loader: (_, period) async => period == '30D'
          ? history(total: 1, sightings: [])
          : history(
              sightings: [sighting(description: 'Restaurado desde Todos')],
            ),
    );
    await tester.tap(find.byKey(const ValueKey('period-30D')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver a Todos'));
    await tester.pumpAndSettle();
    expect(find.text('Restaurado desde Todos'), findsOneWidget);
  });

  testWidgets('32 reporte FINALIZADO conserva acceso al historial', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      loader: (_, _) async => history(status: 'FINALIZADO'),
    );
    expect(find.text('FINALIZADO'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sightings-history-list')),
      findsOneWidget,
    );
  });

  testWidgets(
    '33 la UI no muestra datos del autor aunque sobren en el payload',
    (tester) async {
      final item = sighting();
      item['reporter_name'] = 'Autor Privado';
      item['email'] = 'privado@example.test';
      item['telefono'] = '3000000000';
      await pumpHistory(
        tester,
        loader: (_, _) async => history(sightings: [item]),
      );
      expect(find.text('Autor Privado'), findsNothing);
      expect(find.text('privado@example.test'), findsNothing);
      expect(find.text('3000000000'), findsNothing);
    },
  );

  testWidgets('34 responsive a 320 px sin overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHistory(
      tester,
      loader: (_, _) async => history(
        sightings: [
          sighting(
            description: 'Descripción extensa que debe adaptarse al ancho',
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('35 lista y mapa no generan RenderFlex ni excepciones', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHistory(tester, loader: (_, _) async => history());
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Mapa'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
