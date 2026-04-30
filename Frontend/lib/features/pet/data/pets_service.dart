import 'dart:convert';
import 'package:http/http.dart' as http;

class PetsService {
  static const String baseUrl = 'http://172.24.207.228:3000/api';

  static Future<List<Map<String, dynamic>>> getMyPets({
    required int usuarioId,
  }) async {
    final url = Uri.parse('$baseUrl/pets/my?usuarioId=$usuarioId');

    final response = await http.get(url);

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