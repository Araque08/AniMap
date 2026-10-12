import 'dart:convert';
import '../../../config/api_config.dart';
import '../../auth/data/authenticated_http_client.dart';

class CatalogosService {
  static String get baseUrl => '${ApiConfig.current.baseUrl}/pets';

  static Future<List<Map<String, dynamic>>> obtenerEspecies() async {
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$baseUrl/especies'),
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
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$baseUrl/razas/$especieId'),
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
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$baseUrl/sexos'),
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
