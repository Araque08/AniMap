import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/data/auth_service.dart';

class CatalogosService {
  static const String baseUrl = 'http://192.168.0.8:3000/api/pets';

  static Map<String, String> get _authHeaders {
    final token = AuthService.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('No hay una sesión autenticada');
    }
    return {'Authorization': 'Bearer $token'};
  }

  static Future<List<Map<String, dynamic>>> obtenerEspecies() async {
    final response = await http.get(
      Uri.parse('$baseUrl/especies'),
      headers: _authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('Error obteniendo especies');
    }

    final data = jsonDecode(response.body);

    if (data['ok'] != true) {
      throw Exception(data['message'] ?? 'Error obteniendo especies');
    }

    return List<Map<String, dynamic>>.from(data['especies']);
  }

  static Future<List<Map<String, dynamic>>> obtenerRazas(int especieId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/razas/$especieId'),
      headers: _authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('Error obteniendo razas');
    }

    final data = jsonDecode(response.body);

    if (data['ok'] != true) {
      throw Exception(data['message'] ?? 'Error obteniendo razas');
    }

    return List<Map<String, dynamic>>.from(data['razas']);
  }

  static Future<List<Map<String, dynamic>>> obtenerSexos() async {
    final response = await http.get(
      Uri.parse('$baseUrl/sexos'),
      headers: _authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('Error obteniendo sexos');
    }

    final data = jsonDecode(response.body);

    if (data['ok'] != true) {
      throw Exception(data['message'] ?? 'Error obteniendo sexos');
    }
    return List<Map<String, dynamic>>.from(data['sexos']);
  }
}
