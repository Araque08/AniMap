import 'package:animap/features/sighting/presentation/pages/create_sighting_page.dart';
import 'package:animap/features/report/data/device_location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'image_recognition_test.dart' show image;
import 'sightings_phase1a_test.dart' show allowGeofence, miniMap, scrollTo;

void main() {
  for (final available in [true, false]) {
    testWidgets(
      'initial matched report available=$available never silently becomes independent',
      (tester) async {
        final photo = image();
        var saves = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: CreateSightingPage(
              initialPhoto: photo,
              reporteInicialId: 23,
              reportsLoader: () async => available
                  ? [
                      {
                        'id': 23,
                        'mascota': {'nombre': 'QA elegida', 'especie': 'Perro'},
                      },
                    ]
                  : [],
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
                    expect(reportId, 23);
                    expect(identical(foto, photo), isTrue);
                    expect(
                      await foto!.readAsBytes(),
                      await photo.readAsBytes(),
                    );
                    saves++;
                    return {'id': 41};
                  },
            ),
            routes: {'/home': (_) => const Scaffold(body: Text('published'))},
          ),
        );
        await tester.pumpAndSettle();
        if (available) {
          expect(find.text('Reporte vinculado: QA elegida'), findsOneWidget);
        }
        await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
        await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
        await tester.pumpAndSettle();
        await scrollTo(
          tester,
          find.byKey(const ValueKey('sighting-description')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('sighting-description')),
          'Avistamiento QA controlado',
        );
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await scrollTo(
          tester,
          find.byKey(const ValueKey('sighting-confirm-location')),
        );
        await tester.tap(
          find.byKey(const ValueKey('sighting-confirm-location')),
        );
        await scrollTo(tester, find.byKey(const ValueKey('publish-sighting')));
        await tester.tap(find.byKey(const ValueKey('publish-sighting')));
        await tester.pumpAndSettle();
        expect(saves, available ? 1 : 0);
        if (!available) {
          expect(
            find.text('Selecciona la mascota perdida que viste.'),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets(
    'photo publication requires explicit coordinate confirmation and shares selected photo only after publish',
    (tester) async {
      final photo = image();
      var published = false;
      await tester.pumpWidget(
        MaterialApp(
          home: CreateSightingPage(
            initialPhoto: photo,
            reportsLoader: () async => [],
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
                  expect(identical(foto, photo), isTrue);
                  published = true;
                  return {'id': 41};
                },
          ),
          routes: {'/home': (_) => const Scaffold(body: Text('published'))},
        ),
      );
      await tester.pumpAndSettle();
      expect(published, isFalse);
      await scrollTo(tester, find.byKey(const ValueKey('sighting-use-gps')));
      await tester.tap(find.byKey(const ValueKey('sighting-use-gps')));
      await tester.pumpAndSettle();
      await scrollTo(
        tester,
        find.byKey(const ValueKey('sighting-description')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('sighting-description')),
        'Visto cerca del parque',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const ValueKey('publish-sighting')));
      await tester.tap(find.byKey(const ValueKey('publish-sighting')));
      await tester.pump();
      expect(published, isFalse);
      expect(find.textContaining('Confirma explícitamente'), findsOneWidget);
      await scrollTo(
        tester,
        find.byKey(const ValueKey('sighting-share-contact')),
      );
      final contact = tester.widget<CheckboxListTile>(
        find.byKey(
          const ValueKey('sighting-share-contact'),
          skipOffstage: false,
        ),
      );
      expect(contact.value, isFalse);
      await scrollTo(
        tester,
        find.byKey(const ValueKey('sighting-confirm-location')),
      );
      await tester.tap(find.byKey(const ValueKey('sighting-confirm-location')));
      await scrollTo(tester, find.byKey(const ValueKey('publish-sighting')));
      await tester.tap(find.byKey(const ValueKey('publish-sighting')));
      await tester.pumpAndSettle();
      expect(published, isTrue);
    },
  );
}
