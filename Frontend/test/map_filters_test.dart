import 'dart:convert';
import 'dart:async';

import 'package:animap/features/map/data/map_reports_client.dart';
import 'package:animap/features/map/data/map_filter_selection.dart';
import 'package:animap/features/map/presentation/widgets/map_filters_dialog.dart';
import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> sample(
  String id, {
  String type = 'lost',
  String? species = 'Perro',
  String? color = 'Café',
  String date = '2026-10-17T06:00:00Z',
}) => {
  'id': id,
  'type': type,
  'petName': id,
  'species': species,
  'color': color,
  'description': 'Temporal',
  'dateText': date,
  'lat': 4.65,
  'lng': -74.11,
};

class ReportsFixture extends MapReportsClient {
  int requests = 0;
  @override
  Future<http.Response> getReports(Uri url) async {
    requests++;
    return http.Response(
      jsonEncode({
        'ok': true,
        'data': [
          sample('lost_1'),
          sample('lost_2', species: 'Gato', color: 'Blanco'),
          sample('sighting_3', type: 'sighting', species: null, color: null),
          sample('sighting_4', type: 'sighting', date: '2026-10-16T04:59:59Z'),
          sample('lost_5', type: 'found'),
        ],
      }),
      200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = [
    sample('dog'),
    sample('cat', species: 'Gato', color: 'Blanco'),
    sample('unknown', type: 'sighting', species: null, color: null),
    sample('older', date: '2026-10-17T04:59:59Z'),
  ].map(MapReport.fromJson).toList();
  final day = DateTime(2026, 10, 17);
  final cases = <String, (MapFilterSelection, Set<String>)>{
    'especie sola': (
      const MapFilterSelection(species: 'Perro'),
      {'dog', 'older'},
    ),
    'color solo': (const MapFilterSelection(color: 'Blanco'), {'cat'}),
    'fecha sola Bogotá excluye el segundo anterior al día': (
      MapFilterSelection(from: day, to: day),
      {'dog', 'cat', 'unknown'},
    ),
    'especie + fecha': (
      MapFilterSelection(species: 'Perro', from: day, to: day),
      {'dog'},
    ),
    'color + fecha': (
      MapFilterSelection(color: 'Blanco', from: day, to: day),
      {'cat'},
    ),
    'los tres filtros': (
      MapFilterSelection(species: 'Perro', color: 'Café', from: day, to: day),
      {'dog'},
    ),
    'limpiar incluye independientes': (
      const MapFilterSelection(),
      {'dog', 'cat', 'unknown', 'older'},
    ),
  };
  for (final entry in cases.entries) {
    test(entry.key, () {
      expect(
        data
            .where(
              (r) => entry.value.$1.matches(
                species: r.species,
                color: r.color,
                date: r.occurredAt,
              ),
            )
            .map((r) => r.id)
            .toSet(),
        entry.value.$2,
      );
    });
  }
  test('ambos extremos del rango incluyen el día completo de Bogotá', () {
    final filter = MapFilterSelection(from: day, to: day);
    for (final (date, expected) in [
      ('2026-10-17T05:00:00Z', true),
      ('2026-10-18T04:59:59Z', true),
      ('2026-10-18T05:00:00Z', false),
    ]) {
      expect(
        filter.matches(
          date: MapReport.fromJson(sample('edge', date: date)).occurredAt,
        ),
        expected,
      );
    }
  });
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'];
        messenger.setMockMethodCallHandler(
          MethodChannel('plugins.flutter.io/google_maps_$id'),
          (_) async => null,
        );
        // No native map engine in widget tests; inspect GoogleMap's real markers.
        return Completer<int>().future;
      }
      return null;
    });
  });

  Set<String> markers(WidgetTester tester) => tester
      .widget<GoogleMap>(find.byType(GoogleMap))
      .markers
      .map((m) => m.markerId.value)
      .toSet();

  Future<ReportsFixture> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = ReportsFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: MapPage(
          reportsClient: client,
          locationLoader: () async => throw Exception('GPS no disponible'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return client;
  }

  Future<void> choose(WidgetTester tester, String key, String value) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'especie/color combinan marcadores, conservan IDs coincidentes y Limpiar restaura',
    (tester) async {
      final client = await open(tester);
      expect(markers(tester), {'lost_1', 'lost_2', 'sighting_3', 'sighting_4'});
      await tester.tap(find.byTooltip('Filtrar reportes'));
      await tester.pumpAndSettle();
      await choose(tester, 'map-species-filter', 'Perro');
      await choose(tester, 'map-color-filter', 'Blanco');
      await tester.tap(find.text('Aplicar filtros'));
      await tester.pumpAndSettle();
      expect(markers(tester), isEmpty);
      expect(find.text('No hay resultados con estos filtros'), findsOneWidget);
      await tester.tap(find.text('Limpiar filtros').first);
      await tester.pumpAndSettle();
      expect(markers(tester).length, 4);
      expect(client.requests, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('especie se mantiene al alternar Encontrados y regresar', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Filtrar reportes'));
    await tester.pumpAndSettle();
    await choose(tester, 'map-species-filter', 'Perro');
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();
    expect(markers(tester), {'lost_1', 'sighting_4'});
    await tester.tap(find.text('Encontrados'));
    await tester.pumpAndSettle();
    expect(markers(tester), {'lost_5'});
    await tester.tap(find.text('Activos'));
    await tester.pumpAndSettle();
    expect(markers(tester), {'lost_1', 'sighting_4'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'color individual actualiza mapa y se conserva al cerrar y abrir filtros',
    (tester) async {
      final client = await open(tester);
      await tester.tap(find.byTooltip('Filtrar reportes'));
      await tester.pumpAndSettle();
      await choose(tester, 'map-color-filter', 'Blanco');
      await tester.tap(find.text('Aplicar filtros'));
      await tester.pumpAndSettle();
      expect(markers(tester), {'lost_2'});
      await tester.tap(find.byTooltip('Filtrar reportes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('map-color-filter')),
            )
            .initialValue,
        'Blanco',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(markers(tester), {'lost_2'});
      expect(client.requests, 1);
    },
  );

  testWidgets(
    'fecha aplicada filtra marcadores y el diálogo conserva rango a 320px',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Filtrar reportes'));
      await tester.pumpAndSettle();
      // Return a range through the real dialog route, independently of the native calendar.
      final dialog = tester.element(find.byType(MapFiltersDialog));
      Navigator.pop(
        dialog,
        MapFilterSelection(
          from: DateTime(2026, 10, 17),
          to: DateTime(2026, 10, 17),
        ),
      );
      await tester.pumpAndSettle();
      expect(markers(tester), {'lost_1', 'lost_2', 'sighting_3'});
      await tester.tap(find.byTooltip('Filtrar reportes'));
      await tester.pumpAndSettle();
      expect(find.text('17/10/2026 – 17/10/2026'), findsOneWidget);
      await tester.tap(find.text('Quitar fechas'));
      await tester.tap(find.text('Aplicar filtros'));
      await tester.pumpAndSettle();
      expect(markers(tester).length, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
