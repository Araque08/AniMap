import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/data/authenticated_http_client.dart';
import '../../auth/data/session_manager.dart';

class ReportsException implements Exception {
  final String message;

  ReportsException(this.message);

  @override
  String toString() => message;
}

class ReportsService {
  static const String originUrl = 'http://192.168.0.6:3000';
  static const String baseUrl = '$originUrl/api/reports';

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
    return path.startsWith('http') ? path : '$originUrl$path';
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
