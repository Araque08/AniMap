import 'dart:convert';

import '../../../config/api_config.dart';
import '../../auth/data/authenticated_http_client.dart';

class NotificationHistoryException implements Exception {
  final String message;

  const NotificationHistoryException(this.message);

  @override
  String toString() => message;
}

// Modelo de una notificación.
class AnimapNotification {
  final int id;
  final String titulo;
  final String mensaje;
  final String tipo;
  final bool leida;
  final DateTime fecha;
  final int? reporteId;
  final int? avistamientoId;

  const AnimapNotification({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.tipo,
    required this.leida,
    required this.fecha,
    this.reporteId,
    this.avistamientoId,
  });

  factory AnimapNotification.fromJson(Map<String, dynamic> json) {
    return AnimapNotification(
      id: (json['id'] as num).toInt(),
      titulo: json['titulo']?.toString() ?? '',
      mensaje: json['mensaje']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? 'SISTEMA',
      leida: json['leida'] == true,
      fecha: DateTime.parse(json['fecha'].toString()).toLocal(),
      reporteId: (json['reporteId'] as num?)?.toInt(),
      avistamientoId: (json['avistamientoId'] as num?)?.toInt(),
    );
  }
}

class NotificationHistoryPage {
  final List<AnimapNotification> notificaciones;
  final int pagina;
  final bool hayMas;

  const NotificationHistoryPage({
    required this.notificaciones,
    required this.pagina,
    required this.hayMas,
  });
}

class NotificationHistoryService {
  // =====================================================
  // HU-070: CONSULTAR HISTORIAL
  // =====================================================

  static Future<NotificationHistoryPage> obtenerHistorial({
    int pagina = 1,
  }) async {
    if (pagina < 1) {
      throw const NotificationHistoryException('Número de página inválido.');
    }

    final uri = Uri.parse(
      '${ApiConfig.current.baseUrl}/notifications',
    ).replace(queryParameters: {'pagina': pagina.toString()});

    final response = await AuthenticatedHttpClient.instance.get(uri);

    Map<String, dynamic> body;

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw const FormatException();
      }

      body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const NotificationHistoryException(
        'El servidor devolvió una respuesta inválida.',
      );
    }

    if (response.statusCode != 200 || body['ok'] != true) {
      throw NotificationHistoryException(
        body['message']?.toString() ?? 'No se pudo consultar el historial.',
      );
    }

    final data = body['data'];

    if (data is! Map || data['notificaciones'] is! List) {
      throw const NotificationHistoryException(
        'La información de notificaciones está incompleta.',
      );
    }

    try {
      final lista = (data['notificaciones'] as List)
          .map(
            (item) => AnimapNotification.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();

      return NotificationHistoryPage(
        notificaciones: lista,
        pagina: (data['pagina'] as num).toInt(),
        hayMas: data['hayMas'] == true,
      );
    } catch (_) {
      throw const NotificationHistoryException(
        'No se pudieron interpretar las notificaciones.',
      );
    }
  }

  // =====================================================
  // HU-071: MARCAR NOTIFICACIÓN COMO LEÍDA
  // =====================================================

  static Future<void> marcarComoLeida(int notificacionId) async {
    if (notificacionId <= 0) {
      throw const NotificationHistoryException('Notificación inválida.');
    }

    final uri = Uri.parse(
      '${ApiConfig.current.baseUrl}'
      '/notifications/$notificacionId/read',
    );

    // Envía el token de la sesión automáticamente.
    final response = await AuthenticatedHttpClient.instance.patch(uri);

    Map<String, dynamic> body;

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw const FormatException();
      }

      body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const NotificationHistoryException(
        'El servidor devolvió una respuesta inválida.',
      );
    }

    // Validamos que PostgreSQL haya confirmado
    // el cambio de estado.
    if (response.statusCode != 200 || body['ok'] != true) {
      throw NotificationHistoryException(
        body['message']?.toString() ??
            'No se pudo marcar la notificación como leída.',
      );
    }

    final data = body['data'];

    if (data is! Map || data['id'] != notificacionId || data['leida'] != true) {
      throw const NotificationHistoryException(
        'No se pudo confirmar el cambio de estado.',
      );
    }
  }
}
