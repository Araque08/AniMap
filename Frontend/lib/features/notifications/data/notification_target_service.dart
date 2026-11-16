import 'dart:convert';

import '../../../config/api_config.dart';
import '../../auth/data/authenticated_http_client.dart';
import 'notification_history_service.dart';

// =====================================================
// HU-072: ERRORES AL CONSULTAR CONTENIDO
// =====================================================

class NotificationTargetException implements Exception {
  final String message;

  const NotificationTargetException(this.message);

  @override
  String toString() => message;
}

// =====================================================
// HU-072: BUSCAR REPORTE O AVISTAMIENTO
// =====================================================

class NotificationTargetService {
  // Identifica el contenido asociado a la notificación.
  static String? obtenerIdentificador(AnimapNotification notification) {
    // A photographic match has an authenticated private destination, never a map fallback.
    if (notification.tipo == 'COINCIDENCIA_FOTOGRAFICA') return null;
    // Si está relacionada con un avistamiento,
    // tiene prioridad el avistamiento.
    if (notification.avistamientoId != null &&
        notification.avistamientoId! > 0) {
      return 'sighting_${notification.avistamientoId}';
    }

    // En caso contrario, buscar el reporte.
    if (notification.reporteId != null && notification.reporteId! > 0) {
      return 'lost_${notification.reporteId}';
    }

    // Las notificaciones del sistema pueden no
    // tener contenido asociado.
    return null;
  }

  // =====================================================
  // CONSULTAR EL CONTENIDO REAL EN EL BACKEND
  // =====================================================

  static Future<Map<String, dynamic>?> buscarContenido(
    AnimapNotification notification,
  ) async {
    final identificador = obtenerIdentificador(notification);

    // No tiene un reporte o avistamiento vinculado.
    if (identificador == null) {
      return null;
    }

    return _buscarIdentificador(identificador);
  }

  static Future<Map<String, dynamic>?> buscarAvistamiento(int sightingId) {
    if (sightingId <= 0) return Future.value(null);
    return _buscarIdentificador('sighting_$sightingId');
  }

  static Future<Map<String, dynamic>?> _buscarIdentificador(
    String identificador,
  ) async {
    try {
      final uri = Uri.parse('${ApiConfig.current.baseUrl}/map/reports');

      final response = await AuthenticatedHttpClient.instance
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw const NotificationTargetException(
          'No se pudo consultar el contenido relacionado.',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        throw const NotificationTargetException(
          'El servidor devolvió una respuesta inválida.',
        );
      }

      final data = decoded['data'];

      if (data is! List) {
        throw const NotificationTargetException(
          'La lista de reportes no es válida.',
        );
      }

      // Buscar exactamente el reporte o avistamiento
      // al que hace referencia la notificación.
      for (final item in data) {
        if (item is! Map) continue;

        final reporte = Map<String, dynamic>.from(item);

        if (reporte['id']?.toString() == identificador) {
          return reporte;
        }
      }

      // El contenido ya no está disponible
      // en el catálogo público de AniMap.
      return null;
    } on NotificationTargetException {
      rethrow;
    } catch (_) {
      throw const NotificationTargetException(
        'No fue posible consultar el contenido. '
        'Comprueba tu conexión e inténtalo nuevamente.',
      );
    }
  }
}
