import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../auth/data/auth_service.dart';
import '../../../auth/data/authenticated_http_client.dart';
import '../../../auth/data/session_manager.dart';

class UserAdminException implements Exception {
  final String message;

  const UserAdminException(this.message);

  @override
  String toString() => message;
}

class UserAdminService {
  final AuthenticatedHttpClient client;
  final String baseUrl;

  UserAdminService({
    AuthenticatedHttpClient? client,
    String? baseUrl,
  })  : client = client ?? AuthenticatedHttpClient.instance,
        baseUrl = baseUrl ?? AuthService.baseUrl;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  // =========================================================
  // DECODIFICAR RESPUESTA EXITOSA
  // =========================================================

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            decoded['ok'] == true) {
          return decoded;
        }

        throw UserAdminException(
          decoded['message']?.toString() ??
              'No fue posible realizar la operación.',
        );
      }
    } on FormatException {
      throw const UserAdminException(
        'El servidor devolvió una respuesta no válida.',
      );
    }

    throw const UserAdminException(
      'El servidor devolvió una respuesta no válida.',
    );
  }

  // =========================================================
  // DECODIFICAR ERROR
  // =========================================================

  Map<String, dynamic> _decodeError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}

    return {};
  }

  // =========================================================
  // MANEJO GENERAL DE ERRORES HTTP
  // =========================================================

  Never _throwHttpError(
      http.Response response, {
        String fallback = 'No fue posible realizar la operación.',
      }) {
    final body = _decodeError(response);

    final backendMessage =
    body['message']?.toString();

    switch (response.statusCode) {
      case 400:
        throw UserAdminException(
          backendMessage ??
              'Los datos enviados no son válidos.',
        );

      case 401:
        throw const UserAdminException(
          'Tu sesión expiró. Inicia sesión nuevamente.',
        );

      case 403:
        throw const UserAdminException(
          'No tienes permisos de administrador para realizar esta acción.',
        );

      case 404:
        throw UserAdminException(
          backendMessage ??
              'El usuario no fue encontrado.',
        );

      case 409:
        throw UserAdminException(
          backendMessage ??
              'Existe un conflicto con la información del usuario.',
        );

      default:
        throw UserAdminException(
          backendMessage ?? fallback,
        );
    }
  }

  // =========================================================
  // OBTENER LISTA
  // =========================================================

  List<Map<String, dynamic>> _list(
      http.Response response,
      ) {
    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      _throwHttpError(
        response,
        fallback:
        'No fue posible consultar los usuarios.',
      );
    }

    final decoded = _decode(response);

    final data = decoded['data'];

    if (data is! List) {
      throw const UserAdminException(
        'La lista de usuarios recibida no es válida.',
      );
    }

    return data
        .map(
          (item) => Map<String, dynamic>.from(
        item as Map,
      ),
    )
        .toList();
  }

  // =========================================================
  // OBTENER UN ITEM
  // =========================================================

  Map<String, dynamic> _item(
      http.Response response,
      ) {
    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      _throwHttpError(response);
    }

    final decoded = _decode(response);

    final data = decoded['data'];

    if (data is! Map) {
      throw const UserAdminException(
        'La información del usuario recibida no es válida.',
      );
    }

    return Map<String, dynamic>.from(data);
  }

  // =========================================================
  // LISTAR USUARIOS
  // =========================================================

  Future<List<Map<String, dynamic>>> getUsers({
    String? search,
    String? estado,
    String? rol,
  }) async {
    try {
      final query = <String, String>{};

      if (search != null &&
          search.trim().isNotEmpty) {
        query['search'] = search.trim();
      }

      if (estado != null &&
          estado.trim().isNotEmpty) {
        query['estado'] =
            estado.trim().toUpperCase();
      }

      if (rol != null &&
          rol.trim().isNotEmpty) {
        query['rol'] =
            rol.trim().toUpperCase();
      }

      final uri = Uri.parse(
        '$baseUrl/users',
      ).replace(
        queryParameters:
        query.isEmpty ? null : query,
      );

      final response =
      await client.get(uri);

      return _list(response);
    } on UserAdminException {
      rethrow;
    } on SessionInvalidException {
      throw const UserAdminException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const UserAdminException(
        'No hay conexión con el servidor. Intenta nuevamente.',
      );
    } catch (_) {
      throw const UserAdminException(
        'No fue posible cargar los usuarios.',
      );
    }
  }

  // =========================================================
  // OBTENER USUARIO POR ID
  // =========================================================

  Future<Map<String, dynamic>> getUser(
      int id,
      ) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/users/$id'),
      );

      return _item(response);
    } on UserAdminException {
      rethrow;
    } on SessionInvalidException {
      throw const UserAdminException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const UserAdminException(
        'No hay conexión con el servidor. Intenta nuevamente.',
      );
    } catch (_) {
      throw const UserAdminException(
        'No fue posible cargar la información del usuario.',
      );
    }
  }

  // =========================================================
  // CREAR USUARIO
  // =========================================================

  Future<Map<String, dynamic>> createUser({
    required String nombre,
    required String email,
    String? telefono,
    required String password,
    required String rol,
  }) async {
    try {
      final response =
      await client.post(
        Uri.parse('$baseUrl/users'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'nombre': nombre.trim(),
          'email':
          email.trim().toLowerCase(),
          'telefono':
          telefono?.trim(),
          'password': password,
          'rol':
          rol.trim().toUpperCase(),
        }),
      );

      return _item(response);
    } on UserAdminException {
      rethrow;
    } on SessionInvalidException {
      throw const UserAdminException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const UserAdminException(
        'No hay conexión con el servidor. Intenta nuevamente.',
      );
    } catch (_) {
      throw const UserAdminException(
        'No fue posible crear el usuario.',
      );
    }
  }

  // =========================================================
  // ACTUALIZAR USUARIO
  // =========================================================

  Future<Map<String, dynamic>> updateUser({
    required int id,
    required String nombre,
    required String email,
    String? telefono,
    required String rol,
  }) async {
    try {
      final response =
      await client.put(
        Uri.parse(
          '$baseUrl/users/$id',
        ),
        headers: _jsonHeaders,
        body: jsonEncode({
          'nombre': nombre.trim(),
          'email':
          email.trim().toLowerCase(),
          'telefono':
          telefono?.trim(),
          'rol':
          rol.trim().toUpperCase(),
        }),
      );

      return _item(response);
    } on UserAdminException {
      rethrow;
    } on SessionInvalidException {
      throw const UserAdminException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const UserAdminException(
        'No hay conexión con el servidor. Intenta nuevamente.',
      );
    } catch (_) {
      throw const UserAdminException(
        'No fue posible actualizar el usuario.',
      );
    }
  }

  // =========================================================
  // CAMBIAR ESTADO
  // =========================================================

  Future<Map<String, dynamic>> setUserStatus(
      int id,
      String estado,
      ) async {
    try {
      final response =
      await client.patch(
        Uri.parse(
          '$baseUrl/users/$id/status',
        ),
        headers: _jsonHeaders,
        body: jsonEncode({
          'estado':
          estado.trim().toUpperCase(),
        }),
      );

      return _item(response);
    } on UserAdminException {
      rethrow;
    } on SessionInvalidException {
      throw const UserAdminException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const UserAdminException(
        'No hay conexión con el servidor. Intenta nuevamente.',
      );
    } catch (_) {
      throw const UserAdminException(
        'No fue posible cambiar el estado del usuario.',
      );
    }
  }

  // =========================================================
  // ELIMINAR USUARIO
  // =========================================================
  //
  // El backend realiza eliminación lógica.
  // La cuenta queda INACTIVA.
  // =========================================================

  Future<void> deleteUser(
      int id,
      ) async {
    try {
      final response =
      await client.delete(
        Uri.parse(
          '$baseUrl/users/$id',
        ),
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        _throwHttpError(
          response,
          fallback:
          'No fue posible eliminar el usuario.',
        );
      }

      _decode(response);
    } on UserAdminException {
      rethrow;
    } on SessionInvalidException {
      throw const UserAdminException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
    } on SessionConnectionException {
      throw const UserAdminException(
        'No hay conexión con el servidor. Intenta nuevamente.',
      );
    } catch (_) {
      throw const UserAdminException(
        'No pudimos eliminar el usuario. Intenta nuevamente.',
      );
    }
  }
}