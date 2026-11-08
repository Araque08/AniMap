import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/report/data/image_recognition_service.dart';
import 'package:animap/features/report/data/mascotas_perdidas_service.dart';
import 'package:animap/features/report/presentation/pages/report_search_page.dart';
import 'package:animap/features/report/presentation/widgets/image_search_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

final bytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
XFile image() => XFile.fromData(bytes, name: 'qa.jpeg', mimeType: 'image/jpeg');
const match = ImageMatch(
  reportId: 23,
  name: 'Mascota QA de nombre muy largo para comprobar el diseño',
  species: 'Perro',
  similarity: 0.96,
  imageUrl: 'http://example.invalid/api/map/images/fixture',
);
const results = RecognitionResults(matches: [match], threshold: 0.8);

class _Storage implements SessionStorage {
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

class _DelayedPhoto extends Fake implements XFile {
  final ready = Completer<Uint8List>();
  @override
  Future<int> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() => ready.future;
}

void main() {
  test(
    'multipart uses API config, authenticated client and only foto; malformed scores rejected',
    () async {
      final session = SessionManager(
        storage: _Storage(),
        authBaseUrl: 'http://example.invalid/api/auth',
      );
      await session.establishSession(
        accessToken: 'fixture-access',
        refreshToken: 'fixture-refresh',
        role: 'USUARIO',
      );
      var calls = 0, score = 0.95;
      final service = ImageRecognitionService(
        sessionManager: session,
        clientFactory: () => MockClient((request) async {
          calls++;
          expect(request.url.path, '/api/recognition/search');
          expect(request.headers['Authorization'], 'Bearer fixture-access');
          expect(request.bodyBytes, isNotEmpty);
          return http.Response(
            jsonEncode({
              'ok': true,
              'threshold': 0.8,
              'matches': [
                {
                  'reportId': 23,
                  'similarity': score,
                  'pet': {'nombre': 'QA', 'especie': 'Perro'},
                  'photo': {'url': '/api/map/images/fixture'},
                },
              ],
            }),
            200,
          );
        }),
      );
      expect((await service.search(image())).matches.single.reportId, 23);
      score = 1.5;
      await expectLater(
        service.search(image()),
        throwsA(isA<RecognitionException>()),
      );
      expect(calls, 2);
      service.dispose();
      session.dispose();
    },
  );

  Future<void> sheet(
    WidgetTester tester, {
    Future<RecognitionResults> Function(XFile)? search,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageSearchSheet(
            initialImage: image(),
            pickImage: (_) async => image(),
            search: search ?? (_) async => results,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'preview, one explicit request, duplicate tap blocked, results and disclaimer',
    (tester) async {
      final pending = Completer<RecognitionResults>();
      var calls = 0;
      await sheet(
        tester,
        search: (_) {
          calls++;
          return pending.future;
        },
      );
      expect(find.byType(Image), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.text('Buscar coincidencias'));
      await tester.pump();
      await tester.tap(find.text('Buscando coincidencias…'));
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(results);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Ver reporte'), 180);
      expect(find.text('Similitud visual: 96.0 %'), findsOneWidget);
      expect(find.textContaining('no confirma'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty result and error preserve query, allow retry and selecting another image',
    (tester) async {
      var fail = true;
      await sheet(
        tester,
        search: (_) async {
          if (fail) throw const RecognitionException('Servicio no disponible');
          return const RecognitionResults(matches: [], threshold: 0.8);
        },
      );
      await tester.tap(find.text('Buscar coincidencias'));
      await tester.pumpAndSettle();
      expect(find.text('Servicio no disponible'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Buscar coincidencias'));
      await tester.pumpAndSettle();
      expect(find.text('No se encontraron mascotas similares'), findsOneWidget);
      await tester.tap(find.text('Elegir otra imagen'));
      await tester.pumpAndSettle();
      expect(find.text('No se encontraron mascotas similares'), findsNothing);
    },
  );

  for (final source in [ImageSource.camera, ImageSource.gallery]) {
    testWidgets(
      'Reportar y Buscar: $source -> preview -> result opens corresponding report',
      (tester) async {
        final sources = <ImageSource>[];
        int? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: ReportarBuscarPage(
              reportsLoader: () async => [],
              imagePicker: (s) async {
                sources.add(s);
                return image();
              },
              imageSearch: (_) async => results,
              onImageMatch: (id) => opened = id,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            source == ImageSource.camera
                ? 'Tomar fotografía'
                : 'Seleccionar de galería',
          ),
        );
        await tester.pumpAndSettle();
        expect(sources, [source]);
        await tester.tap(find.text('Buscar coincidencias'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Ver reporte').hitTestable(),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ImageSearchSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Ver reporte').hitTestable());
        await tester.pumpAndSettle();
        expect(opened, 23);
        expect(find.byType(ReportarBuscarPage), findsOneWidget);
      },
    );
  }

  testWidgets(
    '320px and larger text: preview and long result name do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: ImageSearchSheet(
              initialImage: image(),
              pickImage: (_) async => image(),
              search: (_) async => results,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Buscar coincidencias').hitTestable(),
        150,
      );
      await tester.tap(find.text('Buscar coincidencias'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ver reporte').hitTestable(),
        200,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default result navigation rechecks public report and opens existing detail',
    (tester) async {
      var status = 'lost';
      await tester.pumpWidget(
        MaterialApp(
          home: ReportarBuscarPage(
            reportsLoader: () async => [
              MascotaReporte.fromJson({
                'id': 'lost_23',
                'petName': 'QA detalle',
                'type': status,
                'details': 'Perro · QA · Café',
                'description': 'Reporte de prueba',
                'imageUrls': [],
              }),
            ],
            imagePicker: (_) async => image(),
            imageSearch: (_) async => results,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openMatch() async {
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Seleccionar de galería'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Buscar coincidencias'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Ver reporte').hitTestable(),
          150,
          scrollable: find
              .descendant(
                of: find.byType(ImageSearchSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Ver reporte').hitTestable());
        await tester.pumpAndSettle();
      }

      await openMatch();
      expect(find.text('Información del reporte'), findsOneWidget);
      Navigator.of(tester.element(find.text('Información del reporte'))).pop();
      await tester.pumpAndSettle();
      status = 'found';
      await openMatch();
      expect(find.text('El reporte ya no está disponible.'), findsOneWidget);
      expect(find.text('Información del reporte'), findsNothing);
    },
  );

  test('closing while file loads cannot start a late HTTP search', () async {
    final session = SessionManager(
      storage: _Storage(),
      authBaseUrl: 'http://example.invalid/api/auth',
    );
    var clients = 0;
    final service = ImageRecognitionService(
      sessionManager: session,
      clientFactory: () {
        clients++;
        return MockClient((_) async => http.Response('', 500));
      },
    );
    final photo = _DelayedPhoto();
    final search = service.search(photo);
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    photo.ready.complete(bytes);
    await expectLater(search, throwsA(isA<RecognitionException>()));
    expect(clients, 0);
    session.dispose();
  });

  test('oversized image fails before sending HTTP', () async {
    final session = SessionManager(
      storage: _Storage(),
      authBaseUrl: 'http://example.invalid/api/auth',
    );
    var clients = 0;
    final service = ImageRecognitionService(
      sessionManager: session,
      clientFactory: () {
        clients++;
        return MockClient((_) async => http.Response('', 500));
      },
    );
    await expectLater(
      service.search(
        XFile.fromData(Uint8List(5 * 1024 * 1024 + 1), name: 'qa.jpg'),
      ),
      throwsA(isA<RecognitionException>()),
    );
    expect(clients, 0);
    service.dispose();
    session.dispose();
  });
}
