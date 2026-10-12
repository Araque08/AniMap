import 'package:animap/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('URL obligatoria: no hay fallback al emulador ni a otra PC', () {
    expect(() => ApiConfig.fromBaseUrl(''), throwsArgumentError);
    expect(() => ApiConfig.fromBaseUrl('   '), throwsArgumentError);
  });

  test('acepta backend local explícito en desarrollo', () {
    for (final url in [
      'http://10.0.2.2:3000/api',
      'http://192.168.1.20:3000/api',
      'http://localhost:3000/api',
    ]) {
      expect(ApiConfig.fromBaseUrl(url, requireHttps: false).baseUrl, url);
    }
  });

  test('release rechaza HTTP y acepta backend HTTPS', () {
    expect(
      () =>
          ApiConfig.fromBaseUrl('http://10.0.2.2:3000/api', requireHttps: true),
      throwsArgumentError,
    );
    expect(
      ApiConfig.fromBaseUrl(
        'https://api.example.invalid/api',
        requireHttps: true,
      ).baseUrl,
      'https://api.example.invalid/api',
    );
  });

  test('normaliza slash final sin duplicar /api en rutas o fotos', () {
    final config = ApiConfig.fromBaseUrl(
      '  https://api.example.invalid:8443/api///  ',
    );
    expect(config.baseUrl, 'https://api.example.invalid:8443/api');
    expect(config.originUrl, 'https://api.example.invalid:8443');
    expect(
      config.resolveUrl('/api/pets/1/images/photo'),
      'https://api.example.invalid:8443/api/pets/1/images/photo',
    );
    expect(
      config.resolveUrl('api/pets/1/images/photo'),
      'https://api.example.invalid:8443/api/pets/1/images/photo',
    );
    expect(
      config.resolveUrl('https://images.example.invalid/photo.png'),
      'https://images.example.invalid/photo.png',
    );
  });

  test('rechaza configuración incompleta, credenciales y query', () {
    for (final url in [
      'api.example.invalid/api',
      'ftp://api.example.invalid/api',
      'http:///api',
      'https://api.example.invalid',
      'https://api.example.invalid/api?token=test-only',
      'https://api.example.invalid/api#fragment',
      'https://test-user:test-only@api.example.invalid/api',
    ]) {
      expect(() => ApiConfig.fromBaseUrl(url), throwsArgumentError);
    }
  });

  test('error de configuración no incluye valores sensibles del input', () {
    try {
      ApiConfig.fromBaseUrl(
        'https://test-user:sensitive-test-value@api.example.invalid/api',
      );
      fail('Debe rechazar credenciales en API_BASE_URL');
    } on ArgumentError catch (error) {
      expect(error.toString(), contains('API_BASE_URL'));
      expect(error.toString(), isNot(contains('sensitive-test-value')));
      expect(error.toString(), isNot(contains('test-user')));
    }
  });
}
