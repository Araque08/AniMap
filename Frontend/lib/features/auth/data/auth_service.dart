import 'dart:convert';

import 'package:http/http.dart' as http;

/*
  Aquí hicimos una excepción personalizada para manejar errores
  relacionados con autenticación.

  De esta forma podemos mostrar en la interfaz los mensajes
  enviados por el backend de AniMap.
*/
class AuthException implements Exception {
  final String message;

  AuthException(this.message);

  @override
  String toString() => message;
}


/*
  Servicio encargado de comunicarse con los endpoints
  relacionados con autenticación y cuenta.
*/
class AuthService {
  /*
    Aquí definimos la URL base del backend.

    Actualmente usamos la dirección IP local del computador
    donde está ejecutándose el backend de AniMap.

    El dispositivo móvil debe encontrarse conectado a la misma
    red para poder acceder a esta dirección.

    Backend:
    http://192.168.0.8:3000
  */
  static const String baseUrl = 'http://192.168.0.8:3000/api';


  /*
    ============================================================
    REGISTRO
    ============================================================
  */

  /*
    Aquí hicimos el método para registrar usuarios.

    Envía los datos del formulario al endpoint:

    POST /api/auth/register
  */
  Future<Map<String, dynamic>> register({
    required String nombre,
    required String email,
    required String telefono,
    required String password,
    required bool aceptaTyC,
  }) async {
    final url = Uri.parse(
      '$baseUrl/auth/register',
    );

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

    final Map<String, dynamic> data =
    _decodeResponse(response);

    if (
    response.statusCode >= 200 &&
        response.statusCode < 300
    ) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ??
          'Error al registrar usuario',
    );
  }


  /*
    ============================================================
    INICIO DE SESIÓN
    ============================================================
  */

  /*
    Aquí hicimos el método para iniciar sesión.

    Envía:

    - correo
    - contraseña
    - identificador del dispositivo

    al endpoint:

    POST /api/auth/login
  */
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    final url = Uri.parse(
      '$baseUrl/auth/login',
    );

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

    final Map<String, dynamic> data =
    _decodeResponse(response);

    if (
    response.statusCode >= 200 &&
        response.statusCode < 300
    ) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ??
          'Error al iniciar sesión',
    );
  }


  /*
    ============================================================
    VERIFICACIÓN DE CUENTA
    ============================================================
  */

  /*
    Aquí hicimos el método para verificar la cuenta.

    Envía el correo y el código de 6 dígitos al backend.

    Endpoint:

    POST /api/auth/verify-account
  */
  Future<Map<String, dynamic>> verifyAccount({
    required String email,
    required String code,
  }) async {
    final url = Uri.parse(
      '$baseUrl/auth/verify-account',
    );

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

    final Map<String, dynamic> data =
    _decodeResponse(response);

    if (
    response.statusCode >= 200 &&
        response.statusCode < 300
    ) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ??
          'Error al verificar la cuenta',
    );
  }


  /*
    ============================================================
    REENVIAR CÓDIGO DE VERIFICACIÓN
    ============================================================
  */

  /*
    Este método se usa cuando el usuario no recibió
    el código de verificación o necesita solicitar uno nuevo.

    Endpoint:

    POST /api/auth/resend-verification-code
  */
  Future<Map<String, dynamic>> resendVerificationCode({
    required String email,
  }) async {
    final url = Uri.parse(
      '$baseUrl/auth/resend-verification-code',
    );

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
      }),
    );

    final Map<String, dynamic> data =
    _decodeResponse(response);

    if (
    response.statusCode >= 200 &&
        response.statusCode < 300
    ) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ??
          'Error al reenviar el código',
    );
  }


  /*
    ============================================================
    RECUPERACIÓN DE CONTRASEÑA
    ============================================================
  */

  /*
    PRIMERA ETAPA

    Aquí solicitamos la recuperación de contraseña.

    El usuario proporciona solamente su correo.

    El backend genera un código temporal de 6 dígitos
    y lo envía al correo registrado.

    Endpoint:

    POST /api/auth/forgot-password

    Body:

    {
      "email": "usuario@gmail.com"
    }
  */
  Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    final url = Uri.parse(
      '$baseUrl/auth/forgot-password',
    );

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
      }),
    );

    final Map<String, dynamic> data =
    _decodeResponse(response);

    if (
    response.statusCode >= 200 &&
        response.statusCode < 300
    ) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ??
          'Error al solicitar la recuperación de contraseña',
    );
  }


  /*
    ============================================================
    RESTABLECER CONTRASEÑA
    ============================================================
  */

  /*
    SEGUNDA ETAPA

    Aquí enviamos:

    - correo
    - código recibido
    - contraseña nueva
    - confirmación de contraseña

    El backend valida el código y, si todo está correcto,
    reemplaza la contraseña anterior.

    Endpoint:

    POST /api/auth/reset-password

    Body:

    {
      "email": "usuario@gmail.com",
      "code": "123456",
      "newPassword": "Nueva123*",
      "confirmPassword": "Nueva123*"
    }
  */
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final url = Uri.parse(
      '$baseUrl/auth/reset-password',
    );

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'code': code,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      }),
    );

    final Map<String, dynamic> data =
    _decodeResponse(response);

    if (
    response.statusCode >= 200 &&
        response.statusCode < 300
    ) {
      return data;
    }

    throw AuthException(
      data['message']?.toString() ??
          'Error al restablecer la contraseña',
    );
  }


  /*
    ============================================================
    DECODIFICACIÓN DE RESPUESTAS
    ============================================================
  */

  /*
    Aquí interpretamos la respuesta enviada por el backend.

    Si recibimos JSON válido, lo convertimos en Map.

    Si el backend envía una respuesta que no podemos interpretar,
    devolvemos un mensaje controlado para evitar que la aplicación
    falle directamente.
  */
  Map<String, dynamic> _decodeResponse(
      http.Response response,
      ) {
    try {
      final decoded =
      jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {
        'message':
        'Respuesta inválida del servidor',
      };
    } catch (_) {
      return {
        'message':
        'No se pudo interpretar la respuesta del servidor',
      };
    }
  }
}