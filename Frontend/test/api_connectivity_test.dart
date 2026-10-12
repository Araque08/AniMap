import 'dart:convert';

import 'package:animap/features/auth/data/auth_service.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:animap/features/pet/data/mascotas_service.dart';
import 'package:animap/features/report/data/reports_service.dart';
import 'package:animap/features/sighting/data/sightings_service.dart';
import 'package:animap/features/user/data/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() {
  test('autenticación usa el backend configurado en el build', () async {
    Uri? sentUrl;
    final manager = SessionManager(storage: _MemoryStorage());
    final service = AuthService(
      sessionManager: manager,
      client: MockClient((request) async {
        sentUrl = request.url;
        return http.Response('{"ok":true}', 201);
      }),
    );

    await service.register(
      nombre: 'Prueba',
      email: 'test@example.invalid',
      telefono: '3000000000',
      password: 'test-only',
      aceptaTyC: true,
    );

    expect(sentUrl.toString(), '$_apiBaseUrl/auth/register');
    manager.dispose();
  });

  test('restauración y logout usan el mismo backend configurado', () async {
    final sentUrls = <String>[];
    final storage = _MemoryStorage();
    await storage.write(SessionManager.refreshTokenKey, 'test-refresh');
    final manager = SessionManager(
      storage: storage,
      client: MockClient((request) async {
        sentUrls.add(request.url.toString());
        if (request.url.path.endsWith('/refresh')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'accessToken': 'test-access',
                'refreshToken': 'test-refresh-next',
                'role': 'USUARIO',
              },
            }),
            200,
          );
        }
        return http.Response('{"ok":true}', 200);
      }),
    );

    await manager.bootstrap();
    expect(manager.isAuthenticated, isTrue);
    final result = await manager.logout();

    expect(result.remoteRevoked, isTrue);
    expect(sentUrls, ['$_apiBaseUrl/auth/refresh', '$_apiBaseUrl/auth/logout']);
    expect(manager.isAuthenticated, isFalse);
    manager.dispose();
  });

  test(
    'fotos relativas de perfil, reportes y avistamientos usan el backend',
    () {
      final origin = Uri.parse(_apiBaseUrl).origin;
      expect(
        MascotasService.absoluteImageUrl('/api/pets/1/images/pet-photo'),
        '$origin/api/pets/1/images/pet-photo',
      );
      expect(
        ProfileService.absolutePhotoUrl('/api/profile/photo/current'),
        '$origin/api/profile/photo/current',
      );
      expect(
        ReportsService.imageUrl({'url': '/api/map/images/pet-photo'}),
        '$origin/api/map/images/pet-photo',
      );
      expect(
        SightingsService.absoluteImageUrl(
          '/api/sightings/images/sighting-photo',
        ),
        '$origin/api/sightings/images/sighting-photo',
      );
    },
  );

  test('mapa resuelve sus fotos con el backend configurado', () {
    final origin = Uri.parse(_apiBaseUrl).origin;
    final report = MapReport.fromJson({
      'id': 'lost-1',
      'type': 'lost',
      'lat': 4.65,
      'lng': -74.11,
      'imageUrl': '/api/map/images/principal',
      'imageUrls': ['/api/map/images/principal', '/api/map/images/second'],
    });

    expect(report.imageUrl, '$origin/api/map/images/principal');
    expect(report.imageUrls, [
      '$origin/api/map/images/principal',
      '$origin/api/map/images/second',
    ]);
  });
}

class _MemoryStorage implements SessionStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
