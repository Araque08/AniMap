import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';
import 'session_manager.dart';

class AuthException implements Exception {
  final String message;

  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final SessionManager sessionManager;
  final http.Client _client;

  AuthService({SessionManager? sessionManager, http.Client? client})
    : sessionManager = sessionManager ?? SessionManager.instance,
      _client = client ?? http.Client();

  static String get baseUrl => ApiConfig.current.baseUrl;

  Future<String> getDeviceId() => sessionManager.getDeviceId();

  Future<Map<String, dynamic>> register({
    required String nombre,
    required String email,
    required String telefono,
    required String password,
    required bool aceptaTyC,
  }) async {
    final url = Uri.parse('$baseUrl/auth/register');

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
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
      _extractErrorMessage(data, 'Error al registrar usuario'),
    );
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    final url = Uri.parse('$baseUrl/auth/login');

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'deviceId': deviceId,
      }),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final token = data['data']?['accessToken']?.toString();
      final refreshToken = data['data']?['refreshToken']?.toString();
      final role = data['data']?['user']?['rol']
          ?.toString()
          .trim()
          .toUpperCase();

      if (token == null ||
          token.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        throw AuthException('El servidor no devolvió una sesión válida');
      }
      if (role != 'USUARIO' && role != 'ADMINISTRADOR') {
        throw AuthException('La cuenta no tiene un rol válido asignado');
      }

      await sessionManager.establishSession(
        accessToken: token,
        refreshToken: refreshToken,
        role: role,
      );
      return data;
    }

    throw AuthException(_extractErrorMessage(data, 'Error al iniciar sesión'));
  }

  Future<Map<String, dynamic>> verifyAccount({
    required String email,
    required String code,
  }) async {
    final url = Uri.parse('$baseUrl/auth/verify-account');

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw AuthException(
      _extractErrorMessage(data, 'Error al verificar la cuenta'),
    );
  }

  Future<Map<String, dynamic>> resendVerificationCode({
    required String email,
  }) async {
    final url = Uri.parse('$baseUrl/auth/resend-verification-code');

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw AuthException(
      _extractErrorMessage(data, 'Error al reenviar el código'),
    );
  }

  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final url = Uri.parse('$baseUrl/auth/forgot-password');

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw AuthException(
      _extractErrorMessage(
        data,
        'Error al solicitar la recuperación de contraseña',
      ),
    );
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final url = Uri.parse('$baseUrl/auth/reset-password');

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'code': code,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      }),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw AuthException(
      _extractErrorMessage(data, 'Error al restablecer la contraseña'),
    );
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {'message': 'Respuesta inválida del servidor'};
    } catch (_) {
      return {'message': 'No se pudo interpretar la respuesta del servidor'};
    }
  }

  String _extractErrorMessage(Map<String, dynamic> data, String fallback) {
    final errors = data['errors'];

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

    return data['message']?.toString() ?? fallback;
  }
}
