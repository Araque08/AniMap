import 'dart:convert';
import 'dart:typed_data';

import 'package:animap/features/pet/presentation/pages/pet_photos_management_page.dart';
import 'package:animap/features/report/data/geofence_service.dart';
import 'package:animap/features/report/presentation/pages/create_lost_report_page.dart';
import 'package:animap/features/report/presentation/pages/report_type_selector_page.dart';
import 'package:animap/features/sighting/presentation/pages/create_sighting_page.dart';
import 'package:animap/widgets/bottom_menu_animap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

Uint8List imageBytes(int marker) => Uint8List.fromList([
  ...base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
  marker,
]);

List<Map<String, dynamic>> existingPhotos() => List.generate(
  15,
  (index) => {
    'id': index.toRadixString(16).padLeft(24, '0'),
    'url': '/image/$index',
    'esPrincipal': index == 0,
  },
);

Future<GeofenceCheckResult> allowGeofence(double lat, double lng) async =>
    const GeofenceCheckResult(
      inside: true,
      allowed: true,
      mode: 'ENFORCE',
      areaName: 'Salitre Occidental',
    );

void main() {
  testWidgets('9 selector Reportar conserva barra inferior y no se apila', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ReportTypeSelectorPage()));
    expect(find.byType(BottomMenuAnimap), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pets_rounded));
    await tester.pump();
    expect(find.byType(ReportTypeSelectorPage), findsOneWidget);
  });

  testWidgets('10-14 formularios tienen barra y Reportar vuelve al selector', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateLostReportPage(
          petsLoader: () async => [
            {
              'id': 1,
              'nombre': 'Luna',
              'especie': 'Perro',
              'raza': 'Criolla',
              'tieneReporteActivo': false,
            },
          ],
          reportsLoader: () async => [],
          geofenceChecker: allowGeofence,
        ),
        routes: {'/create-report': (_) => const ReportTypeSelectorPage()},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomMenuAnimap), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pets_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ReportTypeSelectorPage), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [],
          geofenceChecker: allowGeofence,
        ),
        routes: {'/create-report': (_) => const ReportTypeSelectorPage()},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomMenuAnimap), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pets_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ReportTypeSelectorPage), findsOneWidget);
  });

  testWidgets('15 cambios sin guardar muestran confirmación', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSightingPage(
          reportsLoader: () async => [],
          geofenceChecker: allowGeofence,
        ),
        routes: {
          '/home': (_) => const Scaffold(body: Text('home-destination')),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sighting-description')),
      'Cambio pendiente',
    );
    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pumpAndSettle();
    expect(find.text('¿Salir sin guardar?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateSightingPage), findsOneWidget);
  });

  testWidgets('23-28 quitar es local y Guardar bloquea 14 sin escrituras', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PetPhotosManagementPage(
          mascotaId: 1,
          photosLoader: ({required mascotaId}) async => existingPhotos(),
          photoBytesLoader: (url) async =>
              imageBytes(int.parse(url.split('/').last)),
          photosPicker: () async => [],
          batchSaver:
              ({
                required mascotaId,
                required originalImageIds,
                required retainedImageIds,
                required newImages,
                principalExistingId,
                principalNewIndex,
              }) async {
                saves += 1;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('delete-photo-000000000000000000000000')),
    );
    await tester.pump();
    expect(
      find.textContaining('14 fotos · mínimo requerido: 15'),
      findsOneWidget,
    );
    expect(saves, 0);
    await tester.tap(find.byKey(const ValueKey('save-photo-changes')));
    await tester.pump();
    expect(
      find.text('Debes mantener mínimo 15 fotografías. Actualmente tienes 14.'),
      findsOneWidget,
    );
    expect(saves, 0);
  });

  testWidgets('29-30 quitar y reponer contenido restaura la referencia', (
    tester,
  ) async {
    List<String>? retained;
    List<XFile>? created;
    final sameOriginal = XFile.fromData(
      imageBytes(0),
      name: 'misma.png',
      mimeType: 'image/png',
      path: 'misma.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PetPhotosManagementPage(
          mascotaId: 1,
          photosLoader: ({required mascotaId}) async => existingPhotos(),
          photoBytesLoader: (url) async =>
              imageBytes(int.parse(url.split('/').last)),
          photosPicker: () async => [sameOriginal],
          batchSaver:
              ({
                required mascotaId,
                required originalImageIds,
                required retainedImageIds,
                required newImages,
                principalExistingId,
                principalNewIndex,
              }) async {
                retained = retainedImageIds;
                created = newImages;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('delete-photo-000000000000000000000000')),
    );
    await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Se restauró la foto original'), findsOneWidget);
    expect(
      find.textContaining('15 fotos · mínimo requerido: 15'),
      findsOneWidget,
    );
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-photo-changes')),
    );
    saveButton.onPressed!();
    await tester.pumpAndSettle();
    expect(retained, hasLength(15));
    expect(retained, contains('000000000000000000000000'));
    expect(created, isEmpty);
  });

  testWidgets(
    '31 duplicado activo se rechaza pero eliminado previamente se acepta',
    (tester) async {
      final duplicate = XFile.fromData(
        imageBytes(1),
        name: 'duplicada.png',
        mimeType: 'image/png',
        path: 'duplicada.png',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async => existingPhotos(),
            photoBytesLoader: (url) async =>
                imageBytes(int.parse(url.split('/').last)),
            photosPicker: () async => [duplicate],
            batchSaver:
                ({
                  required mascotaId,
                  required originalImageIds,
                  required retainedImageIds,
                  required newImages,
                  principalExistingId,
                  principalNewIndex,
                }) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      expect(find.text('Esta foto ya fue agregada.'), findsOneWidget);
      expect(
        find.textContaining('15 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '31 una foto eliminada en una sesión previa puede volver a usarse',
    (tester) async {
      final previousPhoto = XFile.fromData(
        imageBytes(99),
        name: 'foto-anterior.png',
        mimeType: 'image/png',
        path: 'foto-anterior.png',
      );
      List<XFile>? created;
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async => existingPhotos(),
            photoBytesLoader: (url) async =>
                imageBytes(int.parse(url.split('/').last)),
            photosPicker: () async => [previousPhoto],
            batchSaver:
                ({
                  required mascotaId,
                  required originalImageIds,
                  required retainedImageIds,
                  required newImages,
                  principalExistingId,
                  principalNewIndex,
                }) async {
                  created = newImages;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('16 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-photo-changes')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(created, hasLength(1));
    },
  );

  testWidgets('32-37 principal provisional y lote final consistente', (
    tester,
  ) async {
    int? newPrincipalIndex;
    String? existingPrincipal;
    List<XFile>? created;
    final newPhoto = XFile.fromData(
      imageBytes(99),
      name: 'nueva.png',
      mimeType: 'image/png',
      path: 'nueva.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PetPhotosManagementPage(
          mascotaId: 1,
          photosLoader: ({required mascotaId}) async => existingPhotos(),
          photoBytesLoader: (url) async =>
              imageBytes(int.parse(url.split('/').last)),
          photosPicker: () async => [newPhoto],
          batchSaver:
              ({
                required mascotaId,
                required originalImageIds,
                required retainedImageIds,
                required newImages,
                principalExistingId,
                principalNewIndex,
              }) async {
                newPrincipalIndex = principalNewIndex;
                existingPrincipal = principalExistingId;
                created = newImages;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('delete-photo-000000000000000000000000')),
    );
    expect(find.text('Principal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
    await tester.pumpAndSettle();
    final newPrincipal = find.byKey(
      const ValueKey('principal-photo-new-nueva.png'),
    );
    await tester.scrollUntilVisible(
      newPrincipal,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    tester.widget<InkWell>(newPrincipal).onTap!();
    await tester.pump();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    final movedPrincipal = find.byKey(
      const ValueKey('principal-photo-new-nueva.png'),
    );
    expect(tester.widget<InkWell>(movedPrincipal).onTap, isNull);
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('save-photo-changes')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(existingPrincipal, isNull);
    expect(newPrincipalIndex, 0);
    expect(created, hasLength(1));
  });

  testWidgets('38 gestión de fotos no desborda a 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PetPhotosManagementPage(
          mascotaId: 1,
          photosLoader: ({required mascotaId}) async => existingPhotos(),
          photoBytesLoader: (_) async => imageBytes(1),
          photosPicker: () async => [],
          batchSaver:
              ({
                required mascotaId,
                required originalImageIds,
                required retainedImageIds,
                required newImages,
                principalExistingId,
                principalNewIndex,
              }) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
