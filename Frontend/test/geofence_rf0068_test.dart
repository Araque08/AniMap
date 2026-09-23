import 'package:animap/features/report/data/device_location_service.dart';
import 'package:animap/features/report/data/geofence_service.dart';
import 'package:animap/features/report/presentation/pages/create_lost_report_page.dart';
import 'package:animap/features/sighting/data/sightings_service.dart';
import 'package:animap/features/sighting/presentation/pages/create_sighting_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const inside = LatLng(4.651, -74.109);
const outside = LatLng(4.65, -74.1);

const insideResult = GeofenceCheckResult(
  inside: true,
  allowed: true,
  mode: 'ENFORCE',
  areaName: 'Salitre Occidental',
);
const outsideResult = GeofenceCheckResult(
  inside: false,
  allowed: false,
  mode: 'ENFORCE',
  areaName: 'Salitre Occidental',
);

List<Map<String, dynamic>> reportablePets() => [
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

Map<String, dynamic> linkableReport() => {
  'id': 61,
  'mascota': {
    'nombre': 'Luna',
    'especie': 'Perro',
    'raza': 'Criollo',
    'fotoPrincipal': null,
  },
};

Widget miniMap(BuildContext context, LatLng position) => ColoredBox(
  key: const ValueKey('fake-geofence-map'),
  color: Colors.blueGrey,
  child: Text('${position.latitude},${position.longitude}'),
);

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    320,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> pumpLostReport(
  WidgetTester tester, {
  required Future<DeviceLocation> Function() locationLoader,
  required ReportLocationPicker locationPicker,
  required ReportGeofenceChecker checker,
  ReportCreator? creator,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CreateLostReportPage(
        petsLoader: () async => reportablePets(),
        reportsLoader: () async => [],
        locationLoader: locationLoader,
        locationPicker: locationPicker,
        geofenceChecker: checker,
        reportCreator: creator,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpSighting(
  WidgetTester tester, {
  required Future<DeviceLocation> Function() locationLoader,
  required SightingLocationPicker locationPicker,
  required SightingGeofenceChecker checker,
  SightingCreator? creator,
  List<Map<String, dynamic>>? reports,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CreateSightingPage(
        reportsLoader: () async => reports ?? [],
        locationLoader: locationLoader,
        locationPicker: locationPicker,
        geofenceChecker: checker,
        miniMapBuilder: miniMap,
        sightingCreator: creator,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('26 GPS dentro permite continuar', (tester) async {
    await pumpLostReport(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.651, longitude: -74.109),
      locationPicker: (_, _, _) async => inside,
      checker: (_, _) async => insideResult,
    );
    await scrollTo(tester, find.byKey(const ValueKey('lost-report-use-gps')));
    await tester.tap(find.byKey(const ValueKey('lost-report-use-gps')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('geofence-validation-panel')),
      findsNothing,
    );
  });

  testWidgets('27 GPS fuera muestra el mensaje correcto', (tester) async {
    await pumpLostReport(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.65, longitude: -74.1),
      locationPicker: (_, _, _) async => outside,
      checker: (_, _) async => outsideResult,
    );
    await scrollTo(tester, find.byKey(const ValueKey('lost-report-use-gps')));
    await tester.tap(find.byKey(const ValueKey('lost-report-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(outsideAllowedAreaMessage));
    expect(find.text(outsideAllowedAreaMessage), findsOneWidget);
  });

  testWidgets('28 MAPA dentro permite continuar', (tester) async {
    await pumpSighting(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.651, longitude: -74.109),
      locationPicker: (_, _, _) async => inside,
      checker: (_, _) async => insideResult,
    );
    await tester.tap(find.byKey(const ValueKey('sighting-use-map')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('geofence-validation-panel')),
      findsNothing,
    );
  });

  testWidgets('29 MAPA fuera muestra el mismo mensaje', (tester) async {
    await pumpSighting(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.651, longitude: -74.109),
      locationPicker: (_, _, _) async => outside,
      checker: (_, _) async => outsideResult,
    );
    await tester.tap(find.byKey(const ValueKey('sighting-use-map')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(outsideAllowedAreaMessage));
    expect(find.text(outsideAllowedAreaMessage), findsOneWidget);
  });

  testWidgets('30 ubicación fuera conserva el formulario de pérdida', (
    tester,
  ) async {
    await pumpLostReport(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.65, longitude: -74.1),
      locationPicker: (_, _, _) async => outside,
      checker: (_, _) async => outsideResult,
    );
    await tester.enterText(
      find.byKey(const ValueKey('lost-report-description')),
      'Descripción que debe conservarse',
    );
    await scrollTo(tester, find.byKey(const ValueKey('lost-report-reference')));
    await tester.enterText(
      find.byKey(const ValueKey('lost-report-reference')),
      'Frente al parque',
    );
    tester.testTextInput.hide();
    await tester.pump();
    final gpsButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('lost-report-use-gps')),
    );
    gpsButton.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Descripción que debe conservarse'), findsOneWidget);
    expect(find.text('Frente al parque'), findsOneWidget);
    expect(find.text('Luna'), findsWidgets);
  });

  testWidgets('31 ubicación fuera conserva el formulario de avistamiento', (
    tester,
  ) async {
    await pumpSighting(
      tester,
      reports: [linkableReport()],
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.65, longitude: -74.1),
      locationPicker: (_, _, _) async => outside,
      checker: (_, _) async => outsideResult,
    );
    await tester.tap(find.byKey(const ValueKey('linked-sighting')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('linkable-report-61')));
    await tester.enterText(
      find.byKey(const ValueKey('sighting-description')),
      'Avistamiento que debe conservarse',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('sighting-description')));
    expect(find.text('Avistamiento que debe conservarse'), findsOneWidget);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    expect(find.byKey(const ValueKey('linkable-report-61')), findsOneWidget);
  });

  testWidgets('32 Cambiar ubicación permite seleccionar otro punto', (
    tester,
  ) async {
    await pumpSighting(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.65, longitude: -74.1),
      locationPicker: (_, _, _) async => inside,
      checker: (lat, lng) async =>
          lng == inside.longitude ? insideResult : outsideResult,
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const ValueKey('change-geofence-location')),
    );
    await tester.tap(find.byKey(const ValueKey('change-geofence-location')));
    await tester.pump();
    expect(find.text(outsideAllowedAreaMessage), findsNothing);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sighting-use-map')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('geofence-validation-panel')),
      findsNothing,
    );
  });

  testWidgets('33 reintento vuelve a validar sin perder ubicación', (
    tester,
  ) async {
    var attempts = 0;
    await pumpSighting(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.651, longitude: -74.109),
      locationPicker: (_, _, _) async => inside,
      checker: (_, _) async {
        attempts += 1;
        if (attempts == 1) throw Exception('red');
        return insideResult;
      },
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const ValueKey('retry-geofence-validation')),
    );
    await tester.tap(find.byKey(const ValueKey('retry-geofence-validation')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
      find.byKey(const ValueKey('geofence-validation-panel')),
      findsNothing,
    );
  });

  testWidgets('34 error de red no se interpreta como ubicación permitida', (
    tester,
  ) async {
    await pumpSighting(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.651, longitude: -74.109),
      locationPicker: (_, _, _) async => inside,
      checker: (_, _) async => throw Exception('sin red'),
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(geofenceNetworkErrorMessage));
    expect(find.text(geofenceNetworkErrorMessage), findsOneWidget);
    expect(
      find.text('Ubicación dentro de la zona piloto Salitre Occidental.'),
      findsNothing,
    );
  });

  testWidgets('35 rechazo final del backend se muestra correctamente', (
    tester,
  ) async {
    await pumpSighting(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.651, longitude: -74.109),
      locationPicker: (_, _, _) async => inside,
      checker: (_, _) async => insideResult,
      creator:
          ({
            required descripcion,
            reportId,
            required metodo,
            required lat,
            required lng,
            precisionM,
            direccion,
            placeId,
            foto,
          }) async => throw SightingsException(outsideAllowedAreaMessage),
    );
    await tester.enterText(
      find.byKey(const ValueKey('sighting-description')),
      'Descripción válida',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('publish-sighting')));
    await tester.tap(find.byKey(const ValueKey('publish-sighting')));
    await tester.pumpAndSettle();
    expect(find.text(outsideAllowedAreaMessage), findsOneWidget);
  });

  testWidgets('36 panel geofence es responsive a 320 px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpSighting(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.65, longitude: -74.1),
      locationPicker: (_, _, _) async => outside,
      checker: (_, _) async => outsideResult,
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('37 GPS, MAPA y panel no generan RenderFlex ni excepciones', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLostReport(
      tester,
      locationLoader: () async =>
          const DeviceLocation(latitude: 4.65, longitude: -74.1),
      locationPicker: (_, _, _) async => outside,
      checker: (_, _) async => outsideResult,
    );
    await scrollTo(tester, find.byKey(const ValueKey('lost-report-use-gps')));
    await tester.tap(find.byKey(const ValueKey('lost-report-use-gps')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
