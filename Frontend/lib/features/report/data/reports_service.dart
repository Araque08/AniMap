import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';
import '../../auth/data/authenticated_http_client.dart';
import '../../auth/data/session_manager.dart';
import '../../pet/data/mascotas_service.dart';
import 'package:flutter/foundation.dart';

class OwnReportDetails {
  const OwnReportDetails({
    required this.report,
    required this.pet,
    required this.photos,
  });

  final Map<String, dynamic> report;
  final Map<String, dynamic> pet;
  final List<Map<String, dynamic>> photos;
}

class ReportsException implements Exception {
  final String message;

  ReportsException(this.message);

  @override
  String toString() => message;
}

class ReportsService {
  // Avisa a las pantallas cuando se crea un nuevo reporte.
  static final ValueNotifier<int> reportesActualizados =
  ValueNotifier<int>(0);
  static String get baseUrl => '${ApiConfig.current.baseUrl}/reports';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  static Map<String, String> get imageHeaders {
    final token = SessionManager.instance.accessToken;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  static Future<List<Map<String, dynamic>>> getReportablePets() async {
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$baseUrl/pets'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw ReportsException(
        _message(data, 'No se pudieron cargar las mascotas'),
      );
    }
    final pets = data['pets'] as List<dynamic>? ?? const [];
    return pets.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<List<Map<String, dynamic>>> getMyReports() async {
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$baseUrl/my'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw ReportsException(
        _message(data, 'No se pudieron cargar los reportes'),
      );
    }
    final reports = data['reports'] as List<dynamic>? ?? const [];
    return reports
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static void _validateOwnReport(Map<String, dynamic> report, int reportId) {
    final pet = report['mascota'];
    if (report['id'] != reportId ||
        report['mascotaId'] is! int ||
        (report['mascotaId'] as int) <= 0 ||
        pet is! Map ||
        pet['id'] != report['mascotaId'] ||
        report['ubicacion'] is! Map ||
        !['ACTIVO', 'FINALIZADO'].contains(report['estado'])) {
      throw ReportsException('El servidor devolvió un reporte inválido.');
    }
  }

  static Future<Map<String, dynamic>> getOwnReport(
    int reportId, {
    AuthenticatedHttpClient? client,
  }) async {
    if (reportId <= 0) throw ReportsException('El reporte no es válido.');
    final response = await (client ?? AuthenticatedHttpClient.instance).get(
      Uri.parse('$baseUrl/$reportId'),
      headers: _headers,
    );
    final body = _decode(response);
    if (response.statusCode != 200 || body['ok'] != true) {
      throw ReportsException(_message(body, 'No se pudo cargar el reporte.'));
    }
    if (body['report'] is! Map) {
      throw ReportsException('El reporte no está disponible.');
    }
    final report = Map<String, dynamic>.from(body['report'] as Map);
    _validateOwnReport(report, reportId);
    return report;
  }

  static Future<OwnReportDetails> getOwnReportDetails(
    int reportId, {
    Future<Map<String, dynamic>> Function(int)? reportLoader,
    Future<Map<String, dynamic>> Function(int)? petLoader,
    Future<List<Map<String, dynamic>>> Function(int)? photosLoader,
  }) async {
    // Authorize the concrete report before requesting any pet or photo data.
    final report = await (reportLoader ?? getOwnReport)(reportId);
    _validateOwnReport(report, reportId);
    final petId = report['mascotaId'] as int;
    if ((report['mascota'] as Map)['estado'] == 'INACTIVA') {
      // Historical reports remain readable; these pet endpoints return 404.
      return OwnReportDetails(report: report, pet: const {}, photos: const []);
    }
    final results = await Future.wait<Object>([
      (petLoader ?? (id) => MascotasService.obtenerMascotaPorId(mascotaId: id))(
        petId,
      ),
      (photosLoader ??
          (id) => MascotasService.obtenerImagenesMascota(mascotaId: id))(petId),
    ]);
    final pet = results[0] as Map<String, dynamic>;
    if (pet['id'] != petId) {
      throw ReportsException('No se pudieron cargar los datos de la mascota.');
    }
    return OwnReportDetails(
      report: report,
      pet: pet,
      photos: results[1] as List<Map<String, dynamic>>,
    );
  }

  static Future<void> createReport({
    required int mascotaId,
    required String descripcion,
    required bool mostrarContacto,
    required Map<String, dynamic> ubicacion,
  }) async {
    final response = await AuthenticatedHttpClient.instance.post(
      Uri.parse(baseUrl),
      headers: _headers,
      body: jsonEncode({
        'mascotaId': mascotaId,
        'descripcion': descripcion.trim().isEmpty ? null : descripcion.trim(),
        'mostrarContacto': mostrarContacto,
        'ubicacion': ubicacion,
      }),
    );
    final data = _decode(response);
    if (response.statusCode != 201 || data['ok'] != true) {
      throw ReportsException(_message(data, 'No se pudo crear el reporte'));
    }
    // Notificar únicamente cuando el backend confirmó la creación.
    reportesActualizados.value++;
  }

  static Future<void> updateReport({
    required int reportId,
    required String descripcion,
    required bool mostrarContacto,
    Map<String, dynamic>? ubicacion,
  }) async {
    final payload = <String, dynamic>{
      'descripcion': descripcion.trim().isEmpty ? null : descripcion.trim(),
      'mostrarContacto': mostrarContacto,
    };
    if (ubicacion != null) payload['ubicacion'] = ubicacion;
    final response = await AuthenticatedHttpClient.instance.patch(
      Uri.parse('$baseUrl/$reportId'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw ReportsException(
        _message(data, 'No se pudo actualizar el reporte'),
      );
    }
  }

  static Future<void> closeReport(int reportId) async {
    final response = await AuthenticatedHttpClient.instance.post(
      Uri.parse('$baseUrl/$reportId/close'),
      headers: _headers,
    );
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw ReportsException(_message(data, 'No se pudo finalizar el reporte'));
    }
  }

  static String? imageUrl(Map<String, dynamic>? photo) {
    final path = photo?['url']?.toString();
    if (path == null || path.isEmpty) return null;
    return ApiConfig.current.resolveUrl(path);
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic>
          ? decoded
          : {'message': 'Respuesta inválida del servidor'};
    } catch (_) {
      return {'message': 'No se pudo interpretar la respuesta del servidor'};
    }
  }

  static String _message(Map<String, dynamic> data, String fallback) {
    final errors = data['errors'];
    if (errors is List) {
      final messages = errors
          .whereType<Map>()
          .map((error) => error['message']?.toString())
          .whereType<String>()
          .where((message) => message.isNotEmpty)
          .toList();
      if (messages.isNotEmpty) return messages.join('\n');
    }
    return data['message']?.toString() ?? fallback;
  }
}
