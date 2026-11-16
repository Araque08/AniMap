import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/sighting/data/sightings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'image_recognition_test.dart' show image, bytes;
import 'package:animap/features/auth/data/session_storage.dart';

class MemoryStorage implements SessionStorage {
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

class DelayedPhoto extends Fake implements XFile {
  final ready = Completer<int>();
  @override
  String get name => 'photo.png';
  @override
  Future<int> length() => ready.future;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
}

void main() {
  test(
    'multipart preserves UUID, explicit consent and photo bytes across token refresh',
    () async {
      final session = SessionManager(
        storage: MemoryStorage(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'accessToken': 'fresh',
                'refreshToken': 'new-refresh',
                'role': 'USUARIO',
              },
            }),
            200,
          ),
        ),
      );
      await session.establishSession(
        accessToken: 'old',
        refreshToken: 'refresh',
        role: 'USUARIO',
      );
      final bodies = <String>[];
      final tokens = <String?>[];
      final client = AuthenticatedHttpClient(
        sessionManager: session,
        client: MockClient((request) async {
          bodies.add(latin1.decode(request.bodyBytes));
          tokens.add(request.headers['Authorization']);
          return tokens.length == 1
              ? http.Response('{"ok":false,"code":"ACCESS_TOKEN_EXPIRED"}', 401)
              : http.Response('{"ok":true,"sighting":{"id":41}}', 201);
        }),
      );
      final result = await SightingsService.createSighting(
        descripcion: ' Mascota vista ',
        reportId: 23,
        metodo: 'MAPA',
        lat: 4.65,
        lng: -74.1,
        foto: image(),
        solicitudId: 'a742bdb8-f4e9-4db1-bc73-046b787b0a42',
        ubicacionConfirmada: true,
        compartirContacto: false,
        client: client,
      );
      expect(result['id'], 41);
      expect(tokens, ['Bearer old', 'Bearer fresh']);
      for (final body in bodies) {
        expect(body, contains('name="reportId"\r\n\r\n23'));
        expect(body, isNot(contains('name="similarity"')));
        expect(
          body,
          contains(
            'name="solicitudId"\r\n\r\na742bdb8-f4e9-4db1-bc73-046b787b0a42',
          ),
        );
        expect(body, contains('name="ubicacionConfirmada"\r\n\r\ntrue'));
        expect(body, contains('name="compartirContacto"\r\n\r\nfalse'));
        expect(body, contains(latin1.decode(bytes)));
      }
      session.dispose();
    },
  );
  test(
    'account change during image validation never posts under new account',
    () async {
      final session = SessionManager(storage: MemoryStorage());
      await session.establishSession(
        accessToken: 'old',
        refreshToken: 'refresh',
        role: 'USUARIO',
      );
      var requests = 0;
      final client = AuthenticatedHttpClient(
        sessionManager: session,
        client: MockClient((_) async {
          requests++;
          return http.Response('{"ok":true,"sighting":{"id":41}}', 201);
        }),
      );
      final photo = DelayedPhoto();
      final publication = SightingsService.createSighting(
        descripcion: 'Avistamiento',
        metodo: 'MAPA',
        lat: 4.65,
        lng: -74.1,
        foto: photo,
        client: client,
      );
      await session.establishSession(
        accessToken: 'new',
        refreshToken: 'other',
        role: 'USUARIO',
      );
      photo.ready.complete(bytes.length);
      await expectLater(publication, throwsA(isA<SightingsException>()));
      expect(requests, 0);
      session.dispose();
    },
  );
}
