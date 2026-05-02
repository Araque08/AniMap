import 'dart:convert';
import 'package:http/http.dart' as http;

class ProfileService {
  static const String baseUrl = 'http://10.0.2.2:3000';

  static Future<Map<String, dynamic>> obtenerPerfil(int usuarioId) async {
    final url = Uri.parse('$baseUrl/api/profile/$usuarioId');

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Error consultando perfil del usuario');
    }

    final body = jsonDecode(response.body);

    if (body['ok'] != true || body['data'] == null) {
      throw Exception(body['message'] ?? 'Perfil no encontrado');
    }

    return Map<String, dynamic>.from(body['data']);
  }
}