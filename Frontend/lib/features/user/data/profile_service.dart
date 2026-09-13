import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/data/auth_service.dart';

class ProfileException implements Exception {
  final String message;

  ProfileException(this.message);

  @override
  String toString() => message;
}

class ProfileService {
  static const String baseUrl = 'http://192.168.0.8:3000';

  static Future<Map<String, dynamic>> obtenerPerfil() async {
    final token = _requireAccessToken();
    final url = Uri.parse('$baseUrl/api/profile');

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    final body = _decodeResponse(response);

    if (response.statusCode != 200 || body['ok'] != true) {
      throw ProfileException(
        body['message']?.toString() ?? 'Error consultando perfil del usuario',
      );
    }

    if (body['data'] is! Map) {
      throw ProfileException('El servidor devolvió un perfil inválido');
    }

    return Map<String, dynamic>.from(body['data']);
  }

  static Future<Map<String, dynamic>> actualizarPerfil({
    required String nombre,
    required String telefono,
  }) async {
    final token = _requireAccessToken();
    final url = Uri.parse('$baseUrl/api/profile');

    final response = await http.patch(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'nombre': nombre, 'telefono': telefono}),
    );

    final body = _decodeResponse(response);

    if (response.statusCode != 200 || body['ok'] != true) {
      throw ProfileException(_extractErrorMessage(body));
    }

    if (body['data'] is! Map) {
      throw ProfileException('El servidor devolvió un perfil inválido');
    }

    return Map<String, dynamic>.from(body['data']);
  }

  static String _requireAccessToken() {
    final token = AuthService.accessToken;

    if (token == null || token.isEmpty) {
      throw ProfileException(
        'La sesión no está disponible. Inicia sesión nuevamente.',
      );
    }

    return token;
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // La respuesta se convierte en un error controlado más abajo.
    }

    return {'message': 'No se pudo interpretar la respuesta del servidor'};
  }

  static String _extractErrorMessage(Map<String, dynamic> body) {
    final errors = body['errors'];

    if (errors is List) {
      final messages = errors
          .whereType<Map>()
          .map((error) => error['message']?.toString())
          .whereType<String>()
          .where((message) => message.trim().isNotEmpty)
          .toList();

      if (messages.isNotEmpty) {
        return messages.join('\n');
      }
    }

    return body['message']?.toString() ?? 'No se pudo actualizar el perfil';
  }
}
