import 'dart:convert';
import 'dart:typed_data';

import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:animap/features/report/data/device_location_service.dart';
import 'package:animap/features/report/data/geofence_service.dart';
import 'package:animap/features/report/presentation/pages/report_type_selector_page.dart';
import 'package:animap/features/pet/data/pet_image_selection.dart';
import 'package:animap/features/sighting/presentation/pages/create_sighting_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

Map<String, dynamic> linkedReport({String name = 'Luna'}) => {
  'id': 21,
  'mascota': {
    'nombre': name,
    'especie': 'Perro',
    'raza': 'Criollo',
    'fotoPrincipal': null,
  },
};

Future<GeofenceCheckResult> allowGeofence(double lat, double lng) async =>
    const GeofenceCheckResult(
      inside: true,
      allowed: true,
      mode: 'ENFORCE',
      areaName: 'Salitre Occidental',
    );

Widget miniMap(BuildContext context, LatLng position) => ColoredBox(
  key: const ValueKey('fake-sighting-mini-map'),
  color: Colors.blueGrey,
  child: Text('${position.latitude},${position.longitude}'),
);

MapReport sightingReport({bool linked = false, String? imageUrl}) => MapReport(
  id: 'sighting_41',
  title: 'Avistamiento',
  petName: linked ? 'Luna' : 'Sin reporte vinculado',
  details: linked ? 'Perro · Criollo' : 'Avistamiento independiente',
  location: 'Punto marcado en el mapa',
  reference: '',
  description: 'Perro café visto cerca del parque.',
  dateText: '13/09/2026, 10:00',
  occurredAt: DateTime(2026, 9, 13, 10),
  imageUrl: imageUrl,
  position: const LatLng(4.6569, -74.1095),
  type: ReportType.sighting,
  isLinked: linked,
  linkedReportId: linked ? 21 : null,
  showContact: false,
  isOwner: false,
  ownerName: '',
  ownerPhone: '',
  ownerEmail: '',
);

Widget detailMap(BuildContext context, LatLng position, bool interactive) =>
    ColoredBox(
      key: ValueKey(interactive ? 'full-sighting-map' : 'mini-sighting-map'),
      color: Colors.blueGrey,
    );

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    350,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  testWidgets('17 selector Reportar ofrece Pérdida y Avistamiento', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const ReportTypeSelectorPage(),
        routes: {
          '/create-lost-report': (_) =>
              const Scaffold(body: Text('flujo-pérdida')),
          '/create-sighting': (_) =>
              const Scaffold(body: Text('flujo-avistamiento')),
        },
      ),
    );
    expect(find.text('¿Qué deseas reportar?'), findsOneWidget);
    expect(find.text('Mascota perdida'), findsOneWidget);
    expect(find.text('Avistamiento'), findsOneWidget);
  });

  testWidgets('18 la opción Pérdida conserva el flujo existente', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const ReportTypeSelectorPage(),
        routes: {
          '/create-lost-report': (_) =>
              const Scaffold(body: Text('flujo-pérdida')),
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('report-lost-pet')));
    await tester.pumpAndSettle();
    expect(find.text('flujo-pérdida'), findsOneWidget);
  });

  testWidgets('19 registra avistamiento independiente sin inventar reportId', (
    tester,
  ) async {
    int? sentReportId = -1;
    XFile? sentPhoto;
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [linkedReport()],
          geofenceChecker: allowGeofence,
          locationLoader: () async =>
              const DeviceLocation(latitude: 4.65, longitude: -74.10),
          miniMapBuilder: miniMap,
          sightingCreator:
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
              }) async {
                sentReportId = reportId;
                sentPhoto = foto;
                return {'id': 41};
              },
        ),
        routes: {
          '/home': (_) => const Scaffold(body: Text('home-after-sighting')),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sighting-description')),
      '  Animal visto  ',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('publish-sighting')));
    await tester.tap(find.byKey(const ValueKey('publish-sighting')));
    await tester.pumpAndSettle();
    expect(sentReportId, isNull);
    expect(sentPhoto, isNull);
    expect(find.text('home-after-sighting'), findsOneWidget);
  });

  testWidgets('20 registra avistamiento vinculado por reportId', (
    tester,
  ) async {
    int? sentReportId;
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [linkedReport()],
          geofenceChecker: allowGeofence,
          locationLoader: () async =>
              const DeviceLocation(latitude: 4.65, longitude: -74.10),
          miniMapBuilder: miniMap,
          sightingCreator:
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
              }) async {
                sentReportId = reportId;
                return {'id': 41};
              },
        ),
        routes: {
          '/home': (_) => const Scaffold(body: Text('home-after-linked')),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('linked-sighting')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('linkable-report-21')));
    await tester.enterText(
      find.byKey(const ValueKey('sighting-description')),
      'Animal vinculado',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('publish-sighting')));
    await tester.tap(find.byKey(const ValueKey('publish-sighting')));
    await tester.pumpAndSettle();
    expect(sentReportId, 21);
    expect(find.text('home-after-linked'), findsOneWidget);
  });

  testWidgets('21 GPS muestra coordenadas y resumen visual', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [],
          geofenceChecker: allowGeofence,
          locationLoader: () async => const DeviceLocation(
            latitude: 4.651234,
            longitude: -74.101234,
            accuracy: 7,
          ),
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const ValueKey('sighting-location-summary')),
    );
    expect(
      find.byKey(const ValueKey('fake-sighting-mini-map')),
      findsOneWidget,
    );
    expect(find.textContaining('GPS · 4.651234, -74.101234'), findsOneWidget);
  });

  testWidgets('22 permiso GPS rechazado informa y conserva alternativa MAPA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [],
          geofenceChecker: allowGeofence,
          locationLoader: () =>
              Future.error(DeviceLocationException('Permiso denegado')),
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
    await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
    await tester.pump();
    expect(find.textContaining('Permiso denegado'), findsOneWidget);
    expect(find.byKey(const ValueKey('sighting-use-map')), findsOneWidget);
  });

  testWidgets('23 MAPA devuelve y conserva el punto elegido', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [],
          geofenceChecker: allowGeofence,
          locationPicker: (_, _, _) async => const LatLng(4.66, -74.11),
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sighting-use-map')));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const ValueKey('sighting-location-summary')),
    );
    expect(find.textContaining('MAPA · 4.660000, -74.110000'), findsOneWidget);
  });

  testWidgets('24 foto opcional permite preview, reemplazo y retiro', (
    tester,
  ) async {
    final png = XFile.fromData(
      Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
      name: 'avistamiento.png',
      mimeType: 'image/png',
      path: 'avistamiento.png',
    );
    final validation = await validatePetImageSelection(
      selected: [png],
      alreadyAdded: const [],
      maxImages: 1,
    );
    expect(validation.accepted, hasLength(1));
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [],
          geofenceChecker: allowGeofence,
          photoPicker: ({required source}) async => png,
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('choose-sighting-photo')));
    await tester.tap(find.byKey(const ValueKey('choose-sighting-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir de la galería'));
    await tester.pumpAndSettle();
    final preview = find.byKey(
      const ValueKey('sighting-photo-preview'),
      skipOffstage: false,
    );
    expect(preview, findsOneWidget);
    await tester.ensureVisible(preview);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('sighting-photo-preview')),
      findsOneWidget,
    );
    expect(find.text('Reemplazar foto'), findsOneWidget);
    final removeButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('remove-sighting-photo'), skipOffstage: false),
    );
    removeButton.onPressed!();
    await tester.pump();
    expect(find.byKey(const ValueKey('sighting-photo-preview')), findsNothing);
  });

  test('25 pérdida, avistamiento y encontrado tienen colores distintos', () {
    final colors = ReportType.values.map(markerColorForReportType).toSet();
    expect(colors.length, 3);
  });

  testWidgets('26 la foto del avistamiento aparece en la tarjeta del mapa', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapReportPreviewCard(
            report: sightingReport(
              imageUrl: 'https://invalid.local/sighting.png',
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Avistamiento'), findsOneWidget);
  });

  testWidgets(
    '27 usa detalle específico de avistamiento sin contacto de dueño',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SightingDetailPage(
            report: sightingReport(linked: true),
            mapBuilder: detailMap,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Detalle del avistamiento'), findsOneWidget);
      expect(find.text('Ubicación del avistamiento'), findsOneWidget);
      expect(find.text('Fotos de la mascota'), findsNothing);
      expect(find.text('Contacto del dueño'), findsNothing);
    },
  );

  testWidgets('28 independiente no inventa mascota, dueño ni reporte', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SightingDetailPage(
          report: sightingReport(),
          mapBuilder: detailMap,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('independent-sighting-label')),
      findsOneWidget,
    );
    expect(find.text('Luna'), findsNothing);
    expect(find.textContaining('dueño'), findsNothing);
  });

  test('29 mismas coordenadas conservan IDs de avistamiento distintos', () {
    final first = sightingReport();
    final second = MapReport(
      id: 'sighting_42',
      title: first.title,
      petName: first.petName,
      details: first.details,
      location: first.location,
      reference: first.reference,
      description: first.description,
      dateText: first.dateText,
      occurredAt: first.occurredAt,
      imageUrl: first.imageUrl,
      position: first.position,
      type: first.type,
      showContact: false,
      isOwner: false,
      ownerName: '',
      ownerPhone: '',
      ownerEmail: '',
    );
    final markerIds = {MarkerId(first.id), MarkerId(second.id)};
    expect(first.position, second.position);
    expect(markerIds.length, 2);
  });

  testWidgets('30 formulario es responsive a 320 px sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [
            linkedReport(
              name:
                  'Mascota con un nombre deliberadamente muy largo para pantalla angosta',
            ),
          ],
          geofenceChecker: allowGeofence,
          miniMapBuilder: miniMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('linked-sighting')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('tipos desconocidos no se convierten en avistamientos', () {
    expect(
      () => MapReport.fromJson({
        'id': 'unknown_1',
        'type': 'unknown',
        'lat': 4.65,
        'lng': -74.10,
      }),
      throwsFormatException,
    );
  });
}
