
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../config/api_config.dart';
import '../../../auth/data/authenticated_http_client.dart';
import '../../../auth/data/session_manager.dart';

// ==========================================================
// EXCEPCIONES DEL MÓDULO
// ==========================================================

class AdminReportsException implements Exception {
  final String message;

  const AdminReportsException(this.message);

  @override
  String toString() => message;
}

// ==========================================================
// SERVICIO DE REPORTES ADMINISTRATIVOS
// ==========================================================

class AdminReportsService {
  final AuthenticatedHttpClient client;
  final String baseUrl;

  AdminReportsService({
    AuthenticatedHttpClient? client,
    String? baseUrl,
  })  : client = client ?? AuthenticatedHttpClient.instance,
        baseUrl =
            baseUrl ?? '${ApiConfig.current.baseUrl}/admin-reports';

  // ========================================================
  // INTERPRETAR RESPUESTAS
  // ========================================================

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const AdminReportsException(
          'El servidor devolvió datos inválidos.',
        );
      }

      data = decoded;
    } on FormatException {
      throw const AdminReportsException(
        'No se pudo interpretar la respuesta del servidor.',
      );
    }

    if (response.statusCode == 401) {
      throw const AdminReportsException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    }

    if (response.statusCode == 403) {
      throw const AdminReportsException(
        'No tienes permisos para administrar reportes.',
      );
    }

    if (response.statusCode == 404) {
      throw const AdminReportsException(
        'El reporte solicitado no existe.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['ok'] != true) {
      throw AdminReportsException(
        data['message']?.toString() ??
            'No fue posible realizar la consulta.',
      );
    }

    return data;
  }

  // ========================================================
  // LISTAR Y BUSCAR REPORTES
  // ========================================================

  Future<List<Map<String, dynamic>>> getReports({
    String? search,
    String? estado,
  }) async {
    try {
      final query = <String, String>{};

      if (search != null && search.trim().isNotEmpty) {
        query['search'] = search.trim();
      }

      if (estado != null && estado.trim().isNotEmpty) {
        query['estado'] = estado.trim().toUpperCase();
      }

      final uri = Uri.parse(baseUrl).replace(
        queryParameters: query.isEmpty ? null : query,
      );

      final response = await client.get(uri);

      final data = _decode(response);

      final reports = data['reports'];

      if (reports is! List) {
        throw const AdminReportsException(
          'La lista de reportes no es válida.',
        );
      }

      return reports
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } on AdminReportsException {
      rethrow;
    } on SessionInvalidException {
      throw const AdminReportsException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const AdminReportsException(
        'No hay conexión con el servidor.',
      );
    } catch (_) {
      throw const AdminReportsException(
        'No fue posible cargar los reportes.',
      );
    }
  }

  // ========================================================
  // CONSULTAR DETALLE DE UN REPORTE
  // ========================================================

  Future<Map<String, dynamic>> getReport(int reportId) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/$reportId'),
      );

      final data = _decode(response);

      if (data['report'] is! Map) {
        throw const AdminReportsException(
          'La información del reporte no es válida.',
        );
      }

      return Map<String, dynamic>.from(
        data['report'] as Map,
      );
    } on AdminReportsException {
      rethrow;
    } on SessionInvalidException {
      throw const AdminReportsException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const AdminReportsException(
        'No hay conexión con el servidor.',
      );
    } catch (_) {
      throw const AdminReportsException(
        'No fue posible consultar el reporte.',
      );
    }
  }


  // ========================================================
  // HU-076: ACTUALIZAR ESTADO DEL REPORTE Y LA MASCOTA
  // ========================================================

  Future<Map<String, dynamic>> updateReportStatus({
    required int reportId,
    required String estadoReporte,
    required String estadoMascota,
  }) async {
    try {
      // Validar el identificador del reporte.
      if (reportId <= 0) {
        throw const AdminReportsException(
          'El identificador del reporte no es válido.',
        );
      }

      // Preparar los estados.
      final reportStatus =
      estadoReporte.trim().toUpperCase();

      final petStatus =
      estadoMascota.trim().toUpperCase();

      // Validar combinaciones permitidas.
      const allowedCombinations = <String, List<String>>{
        'ACTIVO': ['PERDIDA'],
        'FINALIZADO': ['ACTIVA', 'ENCONTRADA'],
      };

      if (allowedCombinations[reportStatus]
          ?.contains(petStatus) !=
          true) {
        throw const AdminReportsException(
          'Los estados seleccionados no son compatibles.',
        );
      }

      // Preparar la solicitud HTTP.
      final uri = Uri.parse(
        '$baseUrl/$reportId/status',
      );

      final response = await client.patch(
        uri,
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'estadoReporte': reportStatus,
          'estadoMascota': petStatus,
        }),
      );

      // Interpretar respuesta del backend.
      final data = _decode(response);

      final result = data['data'];

      if (result is! Map) {
        throw const AdminReportsException(
          'El servidor no devolvió los estados actualizados.',
        );
      }

      return Map<String, dynamic>.from(result);

    } on AdminReportsException {
      rethrow;

    } on SessionInvalidException {
      throw const AdminReportsException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );

    } on SessionConnectionException {
      throw const AdminReportsException(
        'No hay conexión con el servidor.',
      );

    } catch (_) {
      throw const AdminReportsException(
        'No fue posible actualizar los estados.',
      );
    }
  }

}
