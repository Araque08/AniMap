import 'dart:convert';
import '../../auth/data/authenticated_http_client.dart';
import '../../auth/data/session_manager.dart';

class PetsService {
  static const String baseUrl = 'http://172.20.8.104:3000/api';

  static Map<String, String> get authHeaders {
    final token = SessionManager.instance.accessToken;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  static Future<List<Map<String, dynamic>>> getMyPets() async {
    final url = Uri.parse('$baseUrl/pets/my');

    final response = await AuthenticatedHttpClient.instance.get(url);

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
