import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/data/auth_service.dart';

class PetsService {
  static const String baseUrl = 'http://192.168.0.8:3000/api';

  static Map<String, String> get authHeaders {
    final token = AuthService.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('No hay una sesión autenticada');
    }
    return {'Authorization': 'Bearer $token'};
  }

  static Future<List<Map<String, dynamic>>> getMyPets() async {
    final url = Uri.parse('$baseUrl/pets/my');

    final response = await http.get(url, headers: authHeaders);

    if (response.statusCode != 200) {
      throw Exception('Error consultando las mascotas');
    }

    final data = jsonDecode(response.body);

    if (data['ok'] != true) {
      throw Exception(data['message'] ?? 'No se pudieron cargar las mascotas');
    }

    final mascotas = data['mascotas'] as List;

    return mascotas.map((item) {
      return Map<String, dynamic>.from(item);
    }).toList();
  }
}
