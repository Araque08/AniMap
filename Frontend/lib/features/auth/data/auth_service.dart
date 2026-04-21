import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthException implements Exception {
  final String message;

  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static const String baseUrl = 'http://10.0.2.2:3000/api';

  Future<Map<String, dynamic>> register({
    required String nombre,
    required String email,
    required String telefono,
    required String password,
    required bool aceptaTyC,
  }) async {
    final url = Uri.parse('$baseUrl/auth/register');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'nombre': nombre,
        'email': email,
        'telefono': telefono,
        'password': password,
        'aceptaTyC': aceptaTyC,
      }),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ?? 'Error al registrar usuario',
    );
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    final url = Uri.parse('$baseUrl/auth/login');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'deviceId': deviceId,
      }),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ?? 'Error al iniciar sesión',
    );
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {
        'message': 'Respuesta inválida del servidor',
      };
    } catch (_) {
      return {
        'message': 'No se pudo interpretar la respuesta del servidor',
      };
    }
  }
}