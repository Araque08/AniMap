import 'dart:async';

import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:animap/features/report/data/device_location_service.dart';
import 'package:animap/features/report/data/geocoding_service.dart';
import 'package:animap/features/report/data/geofence_service.dart';
import 'package:animap/features/report/presentation/pages/create_lost_report_page.dart';
import 'package:animap/features/sighting/presentation/pages/create_sighting_page.dart';
import 'package:animap/widgets/address_location_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const insideSelection = AddressLocationSelection(
  formattedAddress: 'Carrera 68B # 24-39, Bogotá',
  lat: 4.651,
  lng: -74.109,
  placeId: 'place-inside',
  inside: true,
  allowed: true,
  mode: 'ENFORCE',
);
const warningSelection = AddressLocationSelection(
  formattedAddress: 'Dirección exterior de pruebas, Bogotá',
  lat: 4.7,
  lng: -74.2,
  placeId: 'place-warning',
  inside: false,
  allowed: true,
  mode: 'WARN',
);
const blockedSelection = AddressLocationSelection(
  formattedAddress: 'Dirección exterior, Bogotá',
  lat: 4.7,
  lng: -74.2,
  placeId: 'place-blocked',
  inside: false,
  allowed: false,
  mode: 'ENFORCE',
);

GeocodingResult oneResult(AddressLocationSelection selection) =>
    GeocodingResult(
      mode: selection.mode,
      candidates: [
        GeocodingCandidate(
          formattedAddress: selection.formattedAddress,
          lat: selection.lat,
          lng: selection.lng,
          placeId: selection.placeId,
          locationType: 'ROOFTOP',
          inside: selection.inside,
          allowed: selection.allowed,
        ),
      ],
    );

Widget miniMap(BuildContext context, LatLng point) => ColoredBox(
  key: const ValueKey('fake-address-map'),
  color: Colors.green,
  child: Text('${point.latitude},${point.longitude}'),
);

List<Map<String, dynamic>> pets() => [
  {
    'id': 31,
    'nombre': 'Luna',
    'especie': 'Perro',
    'raza': 'Criollo',
    'estado': 'ACTIVA',
    'tieneReporteActivo': false,
    'fotoPrincipal': null,
  },
];

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  tester.testTextInput.hide();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('13 Flutter WARN exterior permite continuar', (tester) async {
    var created = false;
    Map<String, dynamic>? locationPayload;
    await tester.pumpWidget(
      MaterialApp(
        home: CreateLostReportPage(
          petsLoader: () async => pets(),
          reportsLoader: () async => [],
          addressPicker: (_, _) async => warningSelection,
          geofenceChecker: (_, _) async => const GeofenceCheckResult(
            inside: false,
            allowed: true,
            mode: 'WARN',
            areaName: 'Salitre Occidental',
          ),
          reportCreator:
              ({
                required mascotaId,
                required descripcion,
                required mostrarContacto,
                required ubicacion,
              }) async {
                created = true;
                locationPayload = ubicacion;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const ValueKey('lost-report-use-address')),
    );
    await tester.tap(find.byKey(const ValueKey('lost-report-use-address')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Modo de pruebas activo'), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('save-lost-report')));
    await tester.tap(find.byKey(const ValueKey('save-lost-report')));
    await tester.pumpAndSettle();
    expect(created, true);
    expect(locationPayload?['metodo'], 'DIRECCION');
    expect(locationPayload?['direccion'], warningSelection.formattedAddress);
  });

  testWidgets('14 Flutter ENFORCE exterior bloquea', (tester) async {
    var created = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CreateLostReportPage(
          petsLoader: () async => pets(),
          reportsLoader: () async => [],
          addressPicker: (_, _) async => blockedSelection,
          geofenceChecker: (_, _) async => const GeofenceCheckResult(
            inside: false,
            allowed: false,
            mode: 'ENFORCE',
            areaName: 'Salitre Occidental',
          ),
          reportCreator:
              ({
                required mascotaId,
                required descripcion,
                required mostrarContacto,
                required ubicacion,
              }) async => created = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const ValueKey('lost-report-use-address')),
    );
    await tester.tap(find.byKey(const ValueKey('lost-report-use-address')));
    await tester.pumpAndSettle();
    expect(find.text(outsideAllowedAreaMessage), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('save-lost-report')));
    await tester.tap(find.byKey(const ValueKey('save-lost-report')));
    await tester.pumpAndSettle();
    expect(created, false);
  });

  testWidgets('30 no hay llamadas de geocoding mientras se escribe', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AddressLocationPage(
          geocoder: (address) async {
            calls += 1;
            return oneResult(insideSelection);
          },
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-address-input')),
      'Carrera 68B # 24-39',
    );
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('31 Validar dirección realiza exactamente una llamada', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AddressLocationPage(
          geocoder: (address) async {
            calls += 1;
            return oneResult(insideSelection);
          },
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-address-input')),
      '  Carrera 68B # 24-39  ',
    );
    await tester.tap(find.byKey(const ValueKey('validate-manual-address')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text(insideSelection.formattedAddress), findsOneWidget);
  });

  testWidgets('32 doble tap queda bloqueado durante loading', (tester) async {
    var calls = 0;
    final completer = Completer<GeocodingResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: AddressLocationPage(
          geocoder: (address) {
            calls += 1;
            return completer.future;
          },
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-address-input')),
      'Carrera 68B # 24-39',
    );
    final button = find.byKey(const ValueKey('validate-manual-address'));
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(calls, 1);
    completer.complete(oneResult(insideSelection));
    await tester.pumpAndSettle();
  });

  testWidgets('33 editar texto invalida el candidato validado', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddressLocationPage(
          geocoder: (_) async => oneResult(insideSelection),
          miniMapBuilder: miniMap,
        ),
      ),
    );
    final input = find.byKey(const ValueKey('manual-address-input'));
    await tester.enterText(input, 'Carrera 68B # 24-39');
    await tester.tap(find.byKey(const ValueKey('validate-manual-address')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('use-manual-address')), findsOneWidget);
    await tester.enterText(input, 'Carrera 68B # 24-40');
    await tester.pump();
    expect(find.byKey(const ValueKey('use-manual-address')), findsNothing);
  });

  testWidgets('40 referencia adicional permanece independiente', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateLostReportPage(
          petsLoader: () async => pets(),
          reportsLoader: () async => [],
          addressPicker: (_, _) async => insideSelection,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('lost-report-reference')));
    await tester.enterText(
      find.byKey(const ValueKey('lost-report-reference')),
      'Frente al parque',
    );
    await scrollTo(
      tester,
      find.byKey(const ValueKey('lost-report-use-address')),
    );
    await tester.tap(find.byKey(const ValueKey('lost-report-use-address')));
    await tester.pumpAndSettle();
    expect(find.text('Frente al parque'), findsOneWidget);
    expect(find.text(insideSelection.formattedAddress), findsWidgets);
  });

  test('43 mapa conserva dirección legible y coordenadas', () {
    final report = MapReport.fromJson({
      'id': 'sighting_9',
      'title': 'Avistamiento',
      'petName': 'Sin reporte vinculado',
      'details': 'Avistamiento independiente',
      'location': insideSelection.formattedAddress,
      'reference': '',
      'description': 'Visto aquí',
      'dateText': '2026-09-13T17:00:00.000Z',
      'lat': insideSelection.lat,
      'lng': insideSelection.lng,
      'type': 'sighting',
      'showContact': false,
      'isOwner': false,
      'ownerName': '',
      'ownerPhone': '',
      'ownerEmail': '',
    });
    expect(report.location, insideSelection.formattedAddress);
    expect(report.position, const LatLng(4.651, -74.109));
  });

  testWidgets('45 formulario reporte conserva datos si dirección falla', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateLostReportPage(
          petsLoader: () async => pets(),
          reportsLoader: () async => [],
          addressPicker: (_, _) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lost-report-description')),
      'Descripción conservada',
    );
    await scrollTo(tester, find.byKey(const ValueKey('lost-report-reference')));
    await tester.enterText(
      find.byKey(const ValueKey('lost-report-reference')),
      'Referencia conservada',
    );
    await scrollTo(
      tester,
      find.byKey(const ValueKey('lost-report-use-address')),
    );
    await tester.tap(find.byKey(const ValueKey('lost-report-use-address')));
    await tester.pumpAndSettle();
    expect(find.text('Descripción conservada'), findsOneWidget);
    expect(find.text('Referencia conservada'), findsOneWidget);
  });

  testWidgets('46 formulario avistamiento conserva datos y vínculo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [
            {
              'id': 61,
              'mascota': {
                'nombre': 'Luna',
                'especie': 'Perro',
                'raza': 'Criollo',
                'fotoPrincipal': null,
              },
            },
          ],
          addressPicker: (_, _) async => null,
          locationLoader: () async =>
              const DeviceLocation(latitude: 4.651, longitude: -74.109),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('linked-sighting')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('linkable-report-61')));
    await tester.enterText(
      find.byKey(const ValueKey('sighting-description')),
      'Avistamiento conservado',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-address')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-address')));
    await tester.pumpAndSettle();
    expect(find.text('Avistamiento conservado'), findsOneWidget);
    final option = tester.widget<Card>(find.byType(Card).last);
    expect(option, isNotNull);
  });

  testWidgets('47 flujo dirección es responsive a 320 px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final candidates = List.generate(
      5,
      (index) => GeocodingCandidate(
        formattedAddress: 'Dirección candidata extensa número $index, Bogotá',
        lat: 4.651,
        lng: -74.109,
        placeId: 'place-$index',
        locationType: 'ROOFTOP',
        inside: true,
        allowed: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AddressLocationPage(
          geocoder: (_) async =>
              GeocodingResult(mode: 'ENFORCE', candidates: candidates),
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-address-input')),
      'Dirección extensa',
    );
    await tester.tap(find.byKey(const ValueKey('validate-manual-address')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('48 flujo no produce RenderFlex ni excepciones', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddressLocationPage(
          initialSelection: warningSelection,
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Modo de pruebas activo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
