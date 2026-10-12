import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._(this.baseUri);

  static final ApiConfig current = ApiConfig.fromBaseUrl(
    const String.fromEnvironment('API_BASE_URL'),
  );

  static ApiConfig initialize() => current;

  factory ApiConfig.fromBaseUrl(
    String value, {
    bool requireHttps = kReleaseMode,
  }) {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw ArgumentError(
        'Define API_BASE_URL mediante --dart-define=API_BASE_URL=<backend>/api.',
      );
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'\s').hasMatch(raw)) {
      throw ArgumentError(
        'API_BASE_URL debe ser una URL HTTP/HTTPS absoluta sin credenciales, '
        'query ni fragmento.',
      );
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (!path.endsWith('/api')) {
      throw ArgumentError('API_BASE_URL debe incluir el prefijo /api.');
    }
    if (requireHttps && uri.scheme != 'https') {
      throw ArgumentError('API_BASE_URL debe usar HTTPS en un build release.');
    }
    return ApiConfig._(uri.replace(path: path));
  }

  final Uri baseUri;

  String get baseUrl => baseUri.toString();
  String get originUrl => baseUri.origin;

  String resolveUrl(String value) =>
      Uri.parse('$originUrl/').resolve(value.trim()).toString();
}
