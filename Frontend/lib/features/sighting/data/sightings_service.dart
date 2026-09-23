import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../auth/data/authenticated_http_client.dart';
import '../../pet/data/pet_image_selection.dart';

class SightingsException implements Exception {
  final String message;

  SightingsException(this.message);

  @override
  String toString() => message;
}

class SightingsService {
  static const String originUrl = 'http://172.20.8.104:3000';
  static const String baseUrl = '$originUrl/api/sightings';

  static Future<List<Map<String, dynamic>>> getLinkableReports() async {
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$baseUrl/linkable-reports'),
      optionalAuthentication: true,
    );
    final body = _decode(response);
    if (response.statusCode != 200 || body['ok'] != true) {
      throw SightingsException(
        _message(body, 'No se pudieron cargar los reportes'),
      );
    }
    final reports = body['reports'] as List<dynamic>? ?? const [];
    return reports
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> getSighting(int sightingId) async {
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$baseUrl/$sightingId'),
      optionalAuthentication: true,
    );
    final body = _decode(response);
    if (response.statusCode != 200 ||
        body['ok'] != true ||
        body['sighting'] is! Map) {
      throw SightingsException(
        _message(body, 'No se pudo cargar el avistamiento'),
      );
    }
    return Map<String, dynamic>.from(body['sighting'] as Map);
  }

  static Future<Map<String, dynamic>> getReportHistory({
    required int reportId,
    String period = 'ALL',
  }) async {
    final uri = Uri.parse(
      '$originUrl/api/reports/$reportId/sightings',
    ).replace(queryParameters: {'period': period});
    final response = await AuthenticatedHttpClient.instance.get(uri);
    final body = _decode(response);
    if (response.statusCode != 200 || body['ok'] != true) {
      throw SightingsException(
        _message(body, 'No se pudo cargar el historial de avistamientos'),
      );
    }
    return body;
  }

  static Future<Map<String, dynamic>> createSighting({
    required String descripcion,
    int? reportId,
    required String metodo,
    required double lat,
    required double lng,
    double? precisionM,
    String? direccion,
    String? placeId,
    XFile? foto,
  }) async {
    if (foto != null) {
      final validation = await validatePetImageSelection(
        selected: [foto],
        alreadyAdded: const [],
        maxImages: 1,
      );
      if (validation.accepted.isEmpty) {
        throw SightingsException(
          validation.rejectionMessage ??
              'Selecciona una imagen JPG, JPEG, PNG o WEBP de máximo 5 MB',
        );
      }
    }

    final response = await AuthenticatedHttpClient.instance.sendMultipart((
      token,
    ) async {
      final request = http.MultipartRequest('POST', Uri.parse(baseUrl));
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['descripcion'] = descripcion.trim();
      request.fields['metodo'] = metodo;
      request.fields['lat'] = lat.toString();
      request.fields['lng'] = lng.toString();
      if (reportId != null) {
        request.fields['reportId'] = reportId.toString();
      }
      if (precisionM != null) {
        request.fields['precisionM'] = precisionM.toString();
      }
      if (direccion != null && direccion.trim().isNotEmpty) {
        request.fields['direccion'] = direccion.trim();
      }
      if (placeId != null && placeId.trim().isNotEmpty) {
        request.fields['placeId'] = placeId.trim();
      }
      if (foto != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'foto',
            foto.path,
            contentType: _contentType(foto.name),
          ),
        );
      }
      return request;
    });
    final body = _decode(response);
    if (response.statusCode != 201 ||
        body['ok'] != true ||
        body['sighting'] is! Map) {
      throw SightingsException(
        _message(body, 'No se pudo registrar el avistamiento'),
      );
    }
    return Map<String, dynamic>.from(body['sighting'] as Map);
  }

  static String? absoluteImageUrl(dynamic value) {
    final path = value?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    return path.startsWith('http') ? path : '$originUrl$path';
  }

  static http.MediaType _contentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return http.MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.png')) return http.MediaType('image', 'png');
    if (lower.endsWith('.webp')) return http.MediaType('image', 'webp');
    throw SightingsException('Formato de imagen no soportado');
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map<String, dynamic>
          ? value
          : {'message': 'Respuesta inválida del servidor'};
    } catch (_) {
      return {'message': 'No se pudo interpretar la respuesta del servidor'};
    }
  }

  static String _message(Map<String, dynamic> body, String fallback) {
    final errors = body['errors'];
    if (errors is List) {
      final messages = errors
          .whereType<Map>()
          .map((item) => item['message']?.toString())
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toList();
      if (messages.isNotEmpty) return messages.join('\n');
    }
    return body['message']?.toString() ?? fallback;
  }
}
