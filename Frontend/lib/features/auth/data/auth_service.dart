import 'dart:convert';
import 'package:http/http.dart' as http;

/*
  Aquí hicimos una excepción personalizada para manejar errores de autenticación.
  Así podemos mostrar mensajes claros en la interfaz cuando el backend responda
  con algún error.
*/
class AuthException implements Exception {
  final String message;

  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  /*
    Aquí definimos la URL base del backend.

    Usamos 10.0.2.2 porque la app está corriendo en un emulador Android.
    En Android Emulator, 10.0.2.2 apunta al localhost del computador.
    Es decir, conecta con el backend que corre en http://localhost:3000.
  */
  static const String baseUrl = 'http://10.0.2.2:3000/api';

  /*
    Aquí hicimos el método para registrar usuarios.
    Este método envía los datos del formulario al endpoint /auth/register.
  */
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

  /*
    Aquí hicimos el método para iniciar sesión.
    Este método envía el correo, la contraseña y el identificador del dispositivo
    al endpoint /auth/login.
  */
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

  /*
    Aquí hicimos el método para verificar la cuenta.
    Este método envía el correo y el código de 6 dígitos al backend.
    Si el código es correcto, el backend marca la cuenta como verificada.
  */
  Future<Map<String, dynamic>> verifyAccount({
    required String email,
    required String code,
  }) async {
    final url = Uri.parse('$baseUrl/auth/verify-account');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'code': code,
      }),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ?? 'Error al verificar la cuenta',
    );
  }

  /*
    Aquí hicimos el método para reenviar el código de verificación.
    Este método se usa cuando el usuario no recibió el código o necesita uno nuevo.
  */
  Future<Map<String, dynamic>> resendVerificationCode({
    required String email,
  }) async {
    final url = Uri.parse('$baseUrl/auth/resend-verification-code');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
      }),
    );

    final Map<String, dynamic> data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ?? 'Error al reenviar el código',
    );
  }

  /*
    Aquí hicimos una función privada para interpretar la respuesta del backend.
    Si el backend responde JSON válido, lo convertimos en Map.
    Si responde algo inválido, devolvemos un mensaje controlado.
  */
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