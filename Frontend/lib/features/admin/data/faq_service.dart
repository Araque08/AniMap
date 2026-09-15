import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../features/auth/data/auth_service.dart';

/*
  Excepción utilizada para mostrar en la interfaz
  los errores enviados por el backend de AniMap.
*/
class FaqException implements Exception {
  final String message;

  FaqException(this.message);

  @override
  String toString() => message;
}

/*
  Servicio encargado de comunicarse con el módulo FAQ
  del backend de AniMap.

  Las consultas públicas no necesitan autenticación.

  Las operaciones administrativas utilizan automáticamente
  el accessToken obtenido durante el inicio de sesión.
*/
class FaqService {
  /*
    Utilizamos la misma URL base configurada
    actualmente en AuthService.
  */
  static const String baseUrl = AuthService.baseUrl;

  /*
    ============================================================
    FAQ PÚBLICAS
    ============================================================
  */

  /*
    GET /api/faqs

    Devuelve únicamente las preguntas activas.

    Permite opcionalmente filtrar por:
    - categoría
    - texto de búsqueda
  */
  Future<List<Map<String, dynamic>>> getPublicFaqs({
    int? categoriaId,
    String? search,
  }) async {
    final queryParameters = <String, String>{};

    if (categoriaId != null) {
      queryParameters['categoriaId'] = categoriaId.toString();
    }

    if (search != null && search.trim().isNotEmpty) {
      queryParameters['search'] = search.trim();
    }

    final uri = Uri.parse(
      '$baseUrl/faqs',
    ).replace(
      queryParameters:
      queryParameters.isEmpty ? null : queryParameters,
    );

    final response = await http.get(uri);

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al consultar las preguntas frecuentes',
    );

    return _extractList(data);
  }

  /*
    ============================================================
    CATEGORÍAS
    ============================================================
  */

  /*
    GET /api/faqs/categories

    Esta consulta es pública porque las categorías también
    se utilizan para organizar las FAQ que verá el usuario.
  */
  Future<List<Map<String, dynamic>>> getCategories() async {
    final url = Uri.parse(
      '$baseUrl/faqs/categories',
    );

    final response = await http.get(url);

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al consultar las categorías',
    );

    return _extractList(data);
  }

  /*
    ============================================================
    FAQ ADMINISTRATIVAS
    ============================================================
  */

  /*
    GET /api/faqs/admin

    Devuelve preguntas activas y archivadas.

    Requiere rol ADMINISTRADOR.
  */
  Future<List<Map<String, dynamic>>> getAdminFaqs({
    int? categoriaId,
    String? search,
  }) async {
    final queryParameters = <String, String>{};

    if (categoriaId != null) {
      queryParameters['categoriaId'] = categoriaId.toString();
    }

    if (search != null && search.trim().isNotEmpty) {
      queryParameters['search'] = search.trim();
    }

    final uri = Uri.parse(
      '$baseUrl/faqs/admin',
    ).replace(
      queryParameters:
      queryParameters.isEmpty ? null : queryParameters,
    );

    final response = await http.get(
      uri,
      headers: _adminHeaders(),
    );

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al consultar las preguntas frecuentes',
    );

    return _extractList(data);
  }

  /*
    ============================================================
    CREAR FAQ
    ============================================================

    POST /api/faqs
  */
  Future<Map<String, dynamic>> createFaq({
    required int categoriaId,
    required String pregunta,
    required String respuesta,
    bool activa = true,
  }) async {
    final url = Uri.parse(
      '$baseUrl/faqs',
    );

    final response = await http.post(
      url,
      headers: _adminHeaders(),
      body: jsonEncode({
        'categoriaId': categoriaId,
        'pregunta': pregunta.trim(),
        'respuesta': respuesta.trim(),
        'activa': activa,
      }),
    );

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al crear la pregunta frecuente',
    );

    return _extractObject(data);
  }

  /*
    ============================================================
    EDITAR FAQ
    ============================================================

    PUT /api/faqs/:id
  */
  Future<Map<String, dynamic>> updateFaq({
    required int id,
    required int categoriaId,
    required String pregunta,
    required String respuesta,
    required bool activa,
  }) async {
    final url = Uri.parse(
      '$baseUrl/faqs/$id',
    );

    final response = await http.put(
      url,
      headers: _adminHeaders(),
      body: jsonEncode({
        'categoriaId': categoriaId,
        'pregunta': pregunta.trim(),
        'respuesta': respuesta.trim(),
        'activa': activa,
      }),
    );

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al actualizar la pregunta frecuente',
    );

    return _extractObject(data);
  }

  /*
    ============================================================
    ACTIVAR / ARCHIVAR FAQ
    ============================================================

    PATCH /api/faqs/:id/status
  */
  Future<Map<String, dynamic>> changeFaqStatus({
    required int id,
    required bool activa,
  }) async {
    final url = Uri.parse(
      '$baseUrl/faqs/$id/status',
    );

    final response = await http.patch(
      url,
      headers: _adminHeaders(),
      body: jsonEncode({
        'activa': activa,
      }),
    );

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al cambiar el estado de la pregunta frecuente',
    );

    return _extractObject(data);
  }

  /*
    ============================================================
    CREAR CATEGORÍA
    ============================================================

    POST /api/faqs/categories
  */
  Future<Map<String, dynamic>> createCategory({
    required String nombre,
    String? descripcion,
  }) async {
    final url = Uri.parse(
      '$baseUrl/faqs/categories',
    );

    final response = await http.post(
      url,
      headers: _adminHeaders(),
      body: jsonEncode({
        'nombre': nombre.trim(),
        'descripcion': descripcion?.trim(),
      }),
    );

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al crear la categoría',
    );

    return _extractObject(data);
  }

  /*
    ============================================================
    EDITAR CATEGORÍA
    ============================================================

    PUT /api/faqs/categories/:id
  */
  Future<Map<String, dynamic>> updateCategory({
    required int id,
    required String nombre,
    String? descripcion,
  }) async {
    final url = Uri.parse(
      '$baseUrl/faqs/categories/$id',
    );

    final response = await http.put(
      url,
      headers: _adminHeaders(),
      body: jsonEncode({
        'nombre': nombre.trim(),
        'descripcion': descripcion?.trim(),
      }),
    );

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al actualizar la categoría',
    );

    return _extractObject(data);
  }

  /*
    ============================================================
    ELIMINAR CATEGORÍA
    ============================================================

    DELETE /api/faqs/categories/:id

    El backend impedirá eliminarla si todavía
    tiene preguntas asociadas.
  */
  Future<Map<String, dynamic>> deleteCategory({
    required int id,
  }) async {
    final url = Uri.parse(
      '$baseUrl/faqs/categories/$id',
    );

    final response = await http.delete(
      url,
      headers: _adminHeaders(),
    );

    final data = _decodeResponse(response);

    _validateResponse(
      response,
      data,
      'Error al eliminar la categoría',
    );

    return _extractObject(data);
  }

  /*
    ============================================================
    HEADERS ADMINISTRATIVOS
    ============================================================

    Recuperamos el token que AuthService guardó
    cuando el administrador inició sesión.
  */
  Map<String, String> _adminHeaders() {
    final token = AuthService.accessToken;

    if (token == null || token.trim().isEmpty) {
      throw FaqException(
        'No existe una sesión administrativa activa',
      );
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /*
    ============================================================
    DECODIFICACIÓN
    ============================================================
  */

  Map<String, dynamic> _decodeResponse(
      http.Response response,
      ) {
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
        'message':
        'No se pudo interpretar la respuesta del servidor',
      };
    }
  }

  /*
    ============================================================
    VALIDACIÓN DE RESPUESTTA HTTP
    ============================================================
  */

  void _validateResponse(
      http.Response response,
      Map<String, dynamic> data,
      String fallback,
      ) {
    if (
    response.statusCode >= 200 &&
        response.statusCode < 300) {
      return;
    }

    final message =
    data['message']?.toString().trim();

    if (message != null && message.isNotEmpty) {
      throw FaqException(message);
    }

    if (response.statusCode == 401) {
      throw FaqException(
        'La sesión ha expirado o no es válida',
      );
    }

    if (response.statusCode == 403) {
      throw FaqException(
        'No tienes permisos para realizar esta acción',
      );
    }

    throw FaqException(fallback);
  }

  /*
    ============================================================
    EXTRAER LISTA
    ============================================================
  */

  List<Map<String, dynamic>> _extractList(
      Map<String, dynamic> response,
      ) {
    final data = response['data'];

    if (data == null) {
      return [];
    }

    if (data is! List) {
      throw FaqException(
        'El servidor devolvió información FAQ inválida',
      );
    }

    return data
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
    )
        .toList();
  }

  /*
    ============================================================
    EXTRAER OBJETO
    ============================================================
  */

  Map<String, dynamic> _extractObject(
      Map<String, dynamic> response,
      ) {
    final data = response['data'];

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    throw FaqException(
      'El servidor devolvió información FAQ inválida',
    );
  }
}