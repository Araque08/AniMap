import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_service.dart';
import '../../auth/data/authenticated_http_client.dart';
import '../../auth/data/session_manager.dart';

class FaqException implements Exception {
  final String message;
  const FaqException(this.message);
  @override
  String toString() => message;
}

class FaqService {
  final AuthenticatedHttpClient client;
  final String baseUrl;

  FaqService({AuthenticatedHttpClient? client, String? baseUrl})
    : client = client ?? AuthenticatedHttpClient.instance,
      baseUrl = baseUrl ?? AuthService.baseUrl;

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            body['ok'] == true) {
          return body;
        }
        throw FaqException(
          body['message']?.toString() ?? 'No fue posible consultar FAQ',
        );
      }
    } on FormatException {
      // El error controlado de abajo evita exponer respuestas sin formato.
    }
    throw const FaqException('Respuesta FAQ no válida');
  }

  List<Map<String, dynamic>> _list(http.Response response) =>
      (_decode(response)['data'] as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  Map<String, dynamic> _item(http.Response response) =>
      Map<String, dynamic>.from(_decode(response)['data'] as Map);

  Map<String, dynamic> _savedItem(http.Response response) {
    if (response.statusCode == 409) {
      throw const FaqException(
        'Ya existe una pregunta frecuente igual en esta categoría.',
      );
    }
    return _item(response);
  }

  Future<List<Map<String, dynamic>>> getPublicFaqs({
    int? categoriaId,
    String? search,
  }) async {
    final query = <String, String>{};
    if (categoriaId != null) query['categoriaId'] = '$categoriaId';
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }
    final uri = Uri.parse(
      '$baseUrl/faqs',
    ).replace(queryParameters: query.isEmpty ? null : query);
    return _list(await client.get(uri, optionalAuthentication: true));
  }

  Future<List<Map<String, dynamic>>> getCategories() async => _list(
    await client.get(
      Uri.parse('$baseUrl/faqs/categories'),
      optionalAuthentication: true,
    ),
  );

  Future<List<Map<String, dynamic>>> getAdminFaqs() async =>
      _list(await client.get(Uri.parse('$baseUrl/faqs/admin')));

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  Future<Map<String, dynamic>> createFaq(Map<String, dynamic> input) async =>
      _savedItem(
        await client.post(
          Uri.parse('$baseUrl/faqs'),
          headers: _jsonHeaders,
          body: jsonEncode(input),
        ),
      );

  Future<Map<String, dynamic>> updateFaq(
    int id,
    Map<String, dynamic> input,
  ) async => _savedItem(
    await client.put(
      Uri.parse('$baseUrl/faqs/$id'),
      headers: _jsonHeaders,
      body: jsonEncode(input),
    ),
  );

  Future<Map<String, dynamic>> setFaqStatus(int id, bool active) async => _item(
    await client.patch(
      Uri.parse('$baseUrl/faqs/$id/status'),
      headers: _jsonHeaders,
      body: jsonEncode({'activa': active}),
    ),
  );

  Future<void> deleteFaq(int id) async {
    try {
      final response = await client.delete(Uri.parse('$baseUrl/faqs/$id'));
      switch (response.statusCode) {
        case 401:
          throw const FaqException(
            'Tu sesión expiró. Inicia sesión nuevamente.',
          );
        case 403:
          throw const FaqException(
            'No tienes permiso para eliminar esta pregunta frecuente.',
          );
        case 404:
          throw const FaqException(
            'La pregunta frecuente ya no existe. Actualiza la lista.',
          );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FaqException(
          'No pudimos eliminar la pregunta frecuente. Intenta nuevamente.',
        );
      }
      _item(response);
    } on FaqException {
      rethrow;
    } on SessionInvalidException {
      throw const FaqException('Tu sesión expiró. Inicia sesión nuevamente.');
    } on SessionConnectionException {
      throw const FaqException(
        'No hay conexión con el servidor. Intenta nuevamente.',
      );
    } catch (_) {
      throw const FaqException(
        'No pudimos eliminar la pregunta frecuente. Revisa tu conexión e intenta nuevamente.',
      );
    }
  }

  Future<Map<String, dynamic>> createCategory(
    String name,
    String? description,
  ) async => _item(
    await client.post(
      Uri.parse('$baseUrl/faqs/categories'),
      headers: _jsonHeaders,
      body: jsonEncode({'nombre': name, 'descripcion': description}),
    ),
  );

  Future<Map<String, dynamic>> updateCategory(
    int id,
    String name,
    String? description,
  ) async => _item(
    await client.put(
      Uri.parse('$baseUrl/faqs/categories/$id'),
      headers: _jsonHeaders,
      body: jsonEncode({'nombre': name, 'descripcion': description}),
    ),
  );

  Future<void> deleteCategory(int id) async {
    _item(await client.delete(Uri.parse('$baseUrl/faqs/categories/$id')));
  }
}
