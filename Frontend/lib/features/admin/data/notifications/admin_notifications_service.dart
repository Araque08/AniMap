
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../config/api_config.dart';
import '../../../auth/data/authenticated_http_client.dart';
import '../../../auth/data/session_manager.dart';

// =====================================================
// HU-049: EXCEPCIONES
// =====================================================

class AdminNotificationsException implements Exception {
  final String message;

  const AdminNotificationsException(this.message);

  @override
  String toString() => message;
}

// =====================================================
// HU-049: SERVICIO ADMINISTRATIVO
// =====================================================

class AdminNotificationsService {
  final AuthenticatedHttpClient client;
  final String baseUrl;

  AdminNotificationsService({
    AuthenticatedHttpClient? client,
    String? baseUrl,
  })  : client = client ?? AuthenticatedHttpClient.instance,
        baseUrl = baseUrl ??
            '${ApiConfig.current.baseUrl}/admin/notifications';

  Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const AdminNotificationsException(
        'El servidor devolvió una respuesta inválida.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const AdminNotificationsException(
        'No se pudo interpretar la respuesta del servidor.',
      );
    }

    if (response.statusCode == 401) {
      throw const AdminNotificationsException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    }

    if (response.statusCode == 403) {
      throw const AdminNotificationsException(
        'No tienes permisos administrativos.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['ok'] != true) {
      throw AdminNotificationsException(
        decoded['message']?.toString() ??
            'No fue posible realizar la operación.',
      );
    }

    final data = decoded['data'];

    if (data is! Map) {
      throw const AdminNotificationsException(
        'La información recibida no es válida.',
      );
    }

    return Map<String, dynamic>.from(data);
  }

  // ===================================================
  // CONSULTAR AUDIENCIAS FILTRADAS POR BARRIO
  // ===================================================

  Future<Map<String, dynamic>> consultarAudiencias({
    String? barrio,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/audiences').replace(
        queryParameters:
            barrio == null ? null : {'barrio': barrio},
      );

      final response = await client.get(uri);

      return _decode(response);
    } on AdminNotificationsException {
      rethrow;
    } on SessionInvalidException {
      throw const AdminNotificationsException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const AdminNotificationsException(
        'No hay conexión con el servidor.',
      );
    } catch (_) {
      throw const AdminNotificationsException(
        'No fue posible consultar los destinatarios.',
      );
    }
  }

  // ===================================================
  // REGISTRAR COMUNICADO ADMINISTRATIVO
  // ===================================================

  Future<Map<String, dynamic>> enviarComunicado({
    required String titulo,
    required String mensaje,
    required String audiencia,
    String? barrio,
  }) async {
    try {
      final response = await client.post(
        Uri.parse(baseUrl),
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'titulo': titulo.trim(),
          'mensaje': mensaje.trim(),
          'audiencia': audiencia,
          'barrio': barrio,
        }),
      );

      return _decode(response);
    } on AdminNotificationsException {
      rethrow;
    } on SessionInvalidException {
      throw const AdminNotificationsException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const AdminNotificationsException(
        'No hay conexión con el servidor.',
      );
    } catch (_) {
      throw const AdminNotificationsException(
        'No fue posible registrar el comunicado. '
        'Verifica el historial antes de reintentarlo.',
      );
    }
  }
}
