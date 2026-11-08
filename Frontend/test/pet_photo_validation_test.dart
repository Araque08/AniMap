import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/pet/data/mascotas_service.dart';
import 'package:animap/features/pet/presentation/pages/pet_photos_management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

Uint8List png(int marker) => Uint8List.fromList([
  ...base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
  marker,
]);

String imageId(int index) => index.toRadixString(16).padLeft(24, '0');
String photoUrl(int index) => '/api/pets/images/${imageId(index)}';
List<Map<String, dynamic>> photos([int count = 15]) => List.generate(
  count,
  (index) => {
    'id': imageId(index),
    'storageRef': imageId(index),
    'metadataId': index + 1,
    'url': photoUrl(index),
    'esPrincipal': index == 0,
    'fecha': '2026-10-01T00:00:00Z',
  },
);
XFile picked(int index) => XFile.fromData(
  png(index),
  name: 'foto-$index.png',
  path: 'foto-$index.png',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response> Function(http.Request) respond;
  final mockClient = MockClient((request) => respond(request));

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    respond = (_) async => throw StateError('Unexpected request');
    // Los clientes singleton se crean dentro de la zona HTTP simulada.
    await http.runWithClient(() async {
      await SessionManager.instance.establishSession(
        accessToken: 'isolated-access',
        refreshToken: 'isolated-refresh',
      );
      AuthenticatedHttpClient.instance;
    }, () => mockClient);
  });

  for (final entry in {
    'image/jpeg': [0xff, 0xd8, 0xff, 9],
    'image/png; charset=binary': png(1),
    'image/webp': [
      ...ascii.encode('RIFF'),
      0,
      0,
      0,
      0,
      ...ascii.encode('WEBP'),
    ],
  }.entries) {
    test('descarga ${entry.key} sin modificar los bytes', () async {
      respond = (_) async => http.Response.bytes(
        entry.value,
        200,
        headers: {'content-type': entry.key},
      );
      expect(await MascotasService.descargarFoto(photoUrl(1)), entry.value);
    });
  }

  for (final entry in {403: 'permiso', 500: 'HTTP 500'}.entries) {
    test('HTTP ${entry.key} produce un error específico y seguro', () async {
      respond = (_) async => http.Response('sensitive-response', entry.key);
      await expectLater(
        MascotasService.descargarFoto(photoUrl(0)),
        throwsA(
          predicate(
            (error) =>
                error.toString().contains(entry.value) &&
                !error.toString().contains('sensitive-response'),
          ),
        ),
      );
    });
  }

  test(
    'la renovación normal reintenta la descarga con el acceso nuevo',
    () async {
      var downloads = 0;
      var refreshes = 0;
      respond = (request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshes++;
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'accessToken': 'isolated-next',
                'refreshToken': 'isolated-refresh-next',
                'role': 'USUARIO',
              },
            }),
            200,
          );
        }
        if (++downloads == 1) {
          return http.Response('{"code":"ACCESS_TOKEN_EXPIRED"}', 401);
        }
        expect(request.headers['Authorization'], 'Bearer isolated-next');
        return http.Response.bytes(
          png(0),
          200,
          headers: {'content-type': 'image/png'},
        );
      };
      expect(await MascotasService.descargarFoto(photoUrl(0)), png(0));
      expect(downloads, 2);
      expect(refreshes, 1);
    },
  );

  test(
    'sesión revocada no descarga ni reintenta con un token antiguo',
    () async {
      var requests = 0;
      respond = (_) async {
        requests++;
        return http.Response('{"code":"SESSION_REVOKED"}', 401);
      };
      await expectLater(
        MascotasService.descargarFoto(photoUrl(0)),
        throwsA(
          predicate((error) => error.toString().contains('Inicia sesión')),
        ),
      );
      expect(requests, 1);
      expect(SessionManager.instance.isAuthenticated, isFalse);
    },
  );

  test('error de conexión no expone detalles internos ni la URL', () async {
    respond = (_) async =>
        throw http.ClientException('sensitive-internal-detail');
    await expectLater(
      MascotasService.descargarFoto(photoUrl(0)),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains('conexión') &&
              !error.toString().contains('sensitive-internal-detail'),
        ),
      ),
    );
  });

  testWidgets('descarga detenida termina con un error de tiempo de espera', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    respond = (_) => pending.future;
    final downloading = MascotasService.descargarFoto(photoUrl(0));
    final assertion = expectLater(
      downloading,
      throwsA(
        predicate((error) => error.toString().contains('tardó demasiado')),
      ),
    );
    await tester.pump(const Duration(seconds: 21));
    await assertion;
    pending.complete(http.Response.bytes(png(0), 200));
    await tester.pump();
  });

  for (final response in [
    http.Response.bytes([], 200, headers: {'content-type': 'image/png'}),
    http.Response(
      '{"error":"no image"}',
      200,
      headers: {'content-type': 'application/octet-stream'},
    ),
    http.Response.bytes(png(0), 200, headers: {'content-type': 'text/html'}),
  ]) {
    test(
      'rechaza contenido vacío o incompatible: ${response.headers['content-type']} / ${response.bodyBytes.length}',
      () async {
        respond = (_) async => response;
        await expectLater(
          MascotasService.descargarFoto(photoUrl(0)),
          throwsA(isA<PetPhotoReadException>()),
        );
      },
    );
  }

  test('descarga una foto válida aunque el backend use octet-stream', () async {
    respond = (request) async {
      expect(request.url.path, photoUrl(0));
      expect(request.headers['Authorization'], 'Bearer isolated-access');
      return http.Response.bytes(
        png(0),
        200,
        headers: {'content-type': 'application/octet-stream'},
      );
    };
    expect(await MascotasService.descargarFoto(photoUrl(0)), png(0));
  });

  test(
    'un 404 distingue una foto ausente de un fallo de comparación',
    () async {
      respond = (_) async => http.Response('{"ok":false}', 404);
      await expectLater(
        MascotasService.descargarFoto(photoUrl(0)),
        throwsA(
          predicate(
            (error) => error.toString().contains('ya no está disponible'),
          ),
        ),
      );
    },
  );

  test('no compara HTML o JSON aunque el servidor indique image/png', () async {
    respond = (_) async => http.Response(
      '<html>Error</html>',
      200,
      headers: {'content-type': 'image/png'},
    );
    await expectLater(
      MascotasService.descargarFoto(photoUrl(0)),
      throwsA(isA<Exception>()),
    );
  });

  test('no envía autenticación a una URL de otro servidor', () async {
    var requests = 0;
    respond = (_) async {
      requests++;
      return http.Response.bytes(
        png(0),
        200,
        headers: {'content-type': 'image/png'},
      );
    };
    await expectLater(
      MascotasService.descargarFoto('https://foreign.invalid${photoUrl(0)}'),
      throwsA(isA<Exception>()),
    );
    expect(requests, 0);
  });

  testWidgets(
    'selección fallida no restaura parcialmente ni altera originales',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async => photos(16),
            photoBytesLoader: (url) async {
              if (url == photoUrl(0)) return png(0);
              throw Exception('Download failed');
            },
            photosPicker: () async => [picked(0), picked(99)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('delete-photo-${imageId(0)}')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('15 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('delete-photo-${imageId(0)}')), findsNothing);
      expect(
        find.byKey(ValueKey('delete-photo-${imageId(1)}')),
        findsOneWidget,
      );
    },
  );

  testWidgets('comparación pendiente bloquea borrar, principal y guardar', (
    tester,
  ) async {
    final pending = Completer<List<int>>();
    await tester.pumpWidget(
      MaterialApp(
        home: PetPhotosManagementPage(
          mascotaId: 1,
          photosLoader: ({required mascotaId}) async => photos(),
          photoBytesLoader: (_) => pending.future,
          photosPicker: () async => [picked(99)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
    await tester.pump();
    final delete = tester.widget<InkWell>(
      find.byKey(ValueKey('delete-photo-${imageId(0)}')),
    );
    final principal = tester.widget<InkWell>(
      find.byKey(ValueKey('principal-photo-${imageId(1)}')),
    );
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-photo-changes')),
    );
    // Completar antes de las aserciones deja el test limpio también en RED.
    pending.complete(png(1));
    await tester.pumpAndSettle();
    expect(delete.onTap, isNull);
    expect(principal.onTap, isNull);
    expect(save.onPressed, isNull);
  });

  testWidgets(
    'fallo al comparar no permite guardar una eliminación pendiente',
    (tester) async {
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async => photos(16),
            photoBytesLoader: (_) async => throw Exception('Download failed'),
            photosPicker: () async => [picked(99)],
            batchSaver:
                ({
                  required mascotaId,
                  required originalImageIds,
                  required retainedImageIds,
                  required newImages,
                  principalExistingId,
                  principalNewIndex,
                }) async {
                  saves++;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('delete-photo-${imageId(0)}')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-photo-changes')));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(
        find.textContaining('15 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
      expect(find.textContaining('No se guardaron cambios'), findsOneWidget);
    },
  );

  testWidgets(
    'reintentar restaura la referencia original y permite guardar sin subirla',
    (tester) async {
      var failDownload = true;
      var saves = 0;
      respond = (request) async {
        if (failDownload) return http.Response('{"ok":false}', 500);
        return http.Response.bytes(
          png(0),
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async => photos(16),
            photosPicker: () async => [picked(0)],
            batchSaver:
                ({
                  required mascotaId,
                  required originalImageIds,
                  required retainedImageIds,
                  required newImages,
                  principalExistingId,
                  principalNewIndex,
                }) async {
                  saves++;
                  expect(
                    originalImageIds.toSet(),
                    photos(16).map((photo) => photo['id']).toSet(),
                  );
                  expect(retainedImageIds, hasLength(16));
                  expect(newImages, isEmpty);
                  expect(principalExistingId, imageId(1));
                  expect(principalNewIndex, isNull);
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('delete-photo-${imageId(0)}')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(
        find.textContaining('15 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      failDownload = false;
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Se restauró la foto original'),
        findsOneWidget,
      );
      expect(
        find.textContaining('16 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-photo-changes')));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(find.text('Fotos actualizadas correctamente.'), findsOneWidget);
    },
  );

  testWidgets(
    'doble selección y guardado simultáneo no envían operaciones duplicadas',
    (tester) async {
      final pending = Completer<List<int>>();
      var picks = 0;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async => photos(),
            photoBytesLoader: (_) => pending.future,
            photosPicker: () async {
              picks++;
              return [picked(99)];
            },
            batchSaver:
                ({
                  required mascotaId,
                  required originalImageIds,
                  required retainedImageIds,
                  required newImages,
                  principalExistingId,
                  principalNewIndex,
                }) async {
                  saves++;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final add = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('add-managed-photos')),
          )
          .onPressed!;
      final save = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-photo-changes')),
          )
          .onPressed!;
      add();
      add();
      save();
      await tester.pump();
      expect(picks, 1);
      expect(saves, 0);
      pending.complete(png(0));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('16 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'fallo al guardar conserva la selección y las imágenes anteriores',
    (tester) async {
      var loads = 0;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async {
              loads++;
              return photos();
            },
            photoBytesLoader: (url) async =>
                png(int.parse(url.split('/').last, radix: 16)),
            photosPicker: () async => [picked(99)],
            batchSaver:
                ({
                  required mascotaId,
                  required originalImageIds,
                  required retainedImageIds,
                  required newImages,
                  principalExistingId,
                  principalNewIndex,
                }) async {
                  saves++;
                  expect(retainedImageIds, hasLength(15));
                  expect(originalImageIds.toSet(), retainedImageIds.toSet());
                  throw Exception('Guardado rechazado');
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-photo-changes')));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(loads, 1);
      expect(
        find.textContaining('16 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('delete-photo-${imageId(0)}')),
        findsOneWidget,
      );
      expect(find.text('Guardado rechazado'), findsOneWidget);
    },
  );

  testWidgets(
    '404 permite preparar reemplazo, pero exige retirar la referencia explícitamente',
    (tester) async {
      var saves = 0;
      respond = (request) async => request.url.path == photoUrl(14)
          ? http.Response('', 404)
          : http.Response.bytes(
              png(int.parse(request.url.path.split('/').last, radix: 16)),
              200,
              headers: {'content-type': 'image/png'},
            );
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async => photos(),
            photosPicker: () async => [picked(99)],
            batchSaver:
                ({
                  required mascotaId,
                  required originalImageIds,
                  required retainedImageIds,
                  required newImages,
                  principalExistingId,
                  principalNewIndex,
                }) async {
                  saves++;
                  expect(
                    originalImageIds.toSet(),
                    photos().map((p) => p['id']).toSet(),
                  );
                  expect(retainedImageIds, hasLength(14));
                  expect(retainedImageIds, isNot(contains(imageId(14))));
                  expect(newImages, hasLength(1));
                  expect(principalExistingId, imageId(0));
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      expect(find.textContaining('15 fotos válidas'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('delete-photo-${imageId(14)}')),
        250,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('pet-photos-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('No disponible'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save-photo-changes')));
      await tester.pumpAndSettle();
      expect(saves, 0);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('delete-photo-${imageId(14)}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-photo-changes')));
      await tester.pumpAndSettle();
      expect(saves, 1);
    },
  );

  testWidgets(
    'recargar reintenta una referencia 404 sin descartarla ni contar menos de 15 válidas',
    (tester) async {
      var missing = true;
      var loads = 0;
      var saves = 0;
      respond = (request) async => missing && request.url.path == photoUrl(14)
          ? http.Response('', 404)
          : http.Response.bytes(
              png(int.parse(request.url.path.split('/').last, radix: 16)),
              200,
              headers: {'content-type': 'image/png'},
            );
      await tester.pumpWidget(
        MaterialApp(
          home: PetPhotosManagementPage(
            mascotaId: 1,
            photosLoader: ({required mascotaId}) async {
              loads++;
              return photos();
            },
            photosPicker: () async => [picked(99)],
            batchSaver:
                ({
                  required mascotaId,
                  required originalImageIds,
                  required retainedImageIds,
                  required newImages,
                  principalExistingId,
                  principalNewIndex,
                }) async {
                  saves++;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('delete-photo-new-foto-99.png')),
        250,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('pet-photos-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('delete-photo-new-foto-99.png')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-photo-changes')));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.textContaining('14 fotos válidas'), findsOneWidget);
      await tester.tap(find.byTooltip('Recargar galería'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      missing = false;
      await tester.tap(find.byTooltip('Recargar galería'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('16 fotos · mínimo requerido: 15'),
        findsOneWidget,
      );
      expect(find.text('No disponible'), findsNothing);
      expect(saves, 0);
    },
  );

  testWidgets('error específico cabe a 320 px sin excepciones', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    respond = (_) async => http.Response('{"ok":false}', 404);
    await tester.pumpWidget(
      MaterialApp(
        home: PetPhotosManagementPage(
          mascotaId: 1,
          photosLoader: ({required mascotaId}) async => photos(),
          photosPicker: () async => [picked(99)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-managed-photos')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ya no está disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
