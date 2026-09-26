import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../auth/data/authenticated_http_client.dart';
import '../../auth/data/session_manager.dart';

class MascotasService {
  static const String baseUrl = 'http://192.168.0.6:3000/api/pets';
  static const String originUrl = 'http://192.168.0.6:3000';

  static Map<String, String> get authHeaders {
    final token = SessionManager.instance.accessToken;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  static http.MediaType _imageContentType(String path) {
    final normalizedPath = path.toLowerCase();

    if (normalizedPath.endsWith('.jpg') || normalizedPath.endsWith('.jpeg')) {
      return http.MediaType('image', 'jpeg');
    }
    if (normalizedPath.endsWith('.png')) {
      return http.MediaType('image', 'png');
    }
    if (normalizedPath.endsWith('.webp')) {
      return http.MediaType('image', 'webp');
    }

    throw ArgumentError('Formato de imagen no soportado');
  }

  static Future<Map<String, dynamic>> registrarMascota({
    required int fkEspecie,
    int? fkRaza,
    required String nombre,
    required String color,
    int? edadAprox,
    String? unidadEdad,
    required String sexo,
    String? observaciones,
    required List<XFile> imagenes,
    required int fotoPrincipalIndex,
  }) async {
    final response = await AuthenticatedHttpClient.instance.sendMultipart((
      token,
    ) async {
      final request = http.MultipartRequest('POST', Uri.parse(baseUrl));
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['fk_especie'] = fkEspecie.toString();
      request.fields['nombre'] = nombre;
      request.fields['color'] = color;
      request.fields['sexo'] = sexo;
      request.fields['foto_principal_index'] = fotoPrincipalIndex.toString();
      if (fkRaza != null) request.fields['fk_raza'] = fkRaza.toString();
      if (edadAprox != null) {
        request.fields['edad_aprox'] = edadAprox.toString();
      }
      if (unidadEdad != null) request.fields['unidad_edad'] = unidadEdad;
      if (observaciones != null && observaciones.trim().isNotEmpty) {
        request.fields['observaciones'] = observaciones.trim();
      }
      for (final imagen in imagenes) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'imagenes',
            imagen.path,
            contentType: _imageContentType(imagen.path),
          ),
        );
      }
      return request;
    });

    final data = jsonDecode(response.body);

    if (response.statusCode != 201 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'Error registrando mascota');
    }

    return data;
  }

  static Future<List<Map<String, dynamic>>> obtenerImagenesMascota({
    required int mascotaId,
  }) async {
    final url = Uri.parse('$baseUrl/$mascotaId/images');

    final response = await AuthenticatedHttpClient.instance.get(url);

    if (response.statusCode != 200) {
      throw Exception('No se pudieron cargar las imágenes');
    }

    final data = jsonDecode(response.body);

    if (data['ok'] != true) {
      throw Exception(data['message'] ?? 'No se pudieron cargar las imágenes');
    }

    final imagenes = data['imagenes'] as List;

    return imagenes.map((item) {
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  static Future<Map<String, dynamic>> obtenerMascotaPorId({
    required int mascotaId,
  }) async {
    final url = Uri.parse('$baseUrl/$mascotaId');

    final response = await AuthenticatedHttpClient.instance.get(url);

    if (response.statusCode != 200) {
      throw Exception('No se pudo cargar la mascota');
    }

    if (response.body.trim().startsWith('<!DOCTYPE html>') ||
        response.body.trim().startsWith('<html')) {
      throw Exception(
        'El backend respondió HTML. Revisa que exista la ruta GET $url',
      );
    }

    final data = jsonDecode(response.body);

    if (data['ok'] != true) {
      throw Exception(data['message'] ?? 'No se pudo cargar la mascota');
    }

    if (data['mascota'] != null) {
      return Map<String, dynamic>.from(data['mascota']);
    }

    if (data['pet'] != null) {
      return Map<String, dynamic>.from(data['pet']);
    }

    if (data['data'] != null) {
      return Map<String, dynamic>.from(data['data']);
    }

    return Map<String, dynamic>.from(data);
  }

  static Future<void> eliminarMascota({required int mascotaId}) async {
    final url = Uri.parse('$baseUrl/$mascotaId');

    final response = await AuthenticatedHttpClient.instance.delete(url);

    if (response.body.trim().startsWith('<!DOCTYPE html>') ||
        response.body.trim().startsWith('<html')) {
      throw Exception(
        'El backend respondió HTML. Revisa que exista la ruta DELETE $url',
      );
    }

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'No se pudo inactivar la mascota');
    }
  }

  static Future<void> actualizarMascota({
    required int mascotaId,
    required int fkEspecie,
    int? fkRaza,
    required String nombre,
    required String color,
    int? edadAprox,
    String? unidadEdad,
    required String sexo,
    required String observaciones,
  }) async {
    final url = Uri.parse('$baseUrl/$mascotaId');

    final body = {
      'fk_especie': fkEspecie,
      'fk_raza': fkRaza,
      'nombre': nombre,
      'color': color,
      'edad_aprox': edadAprox,
      'unidad_edad': unidadEdad,
      'sexo': sexo,
      'observaciones': observaciones,
    };

    final response = await AuthenticatedHttpClient.instance.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.body.trim().startsWith('<!DOCTYPE html>') ||
        response.body.trim().startsWith('<html')) {
      throw Exception(
        'El backend respondió HTML. Revisa que exista la ruta PUT $url',
      );
    }

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'No se pudo actualizar la mascota');
    }
  }

  static Future<void> agregarFotosMascota({
    required int mascotaId,
    required List<XFile> imagenes,
    int fotoPrincipalIndex = 0,
    bool marcarComoPrincipal = false,
  }) async {
    final url = Uri.parse('$baseUrl/$mascotaId/images');

    final response = await AuthenticatedHttpClient.instance.sendMultipart((
      token,
    ) async {
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['foto_principal_index'] = fotoPrincipalIndex.toString();
      request.fields['marcar_como_principal'] = marcarComoPrincipal.toString();
      for (final imagen in imagenes) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'imagenes',
            imagen.path,
            contentType: _imageContentType(imagen.path),
          ),
        );
      }
      return request;
    });

    final data = jsonDecode(response.body);

    if (response.statusCode != 201 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'No se pudieron agregar las fotos');
    }
  }

  static Future<void> establecerFotoPrincipal({
    required int mascotaId,
    required String imageId,
  }) async {
    final response = await AuthenticatedHttpClient.instance.put(
      Uri.parse('$baseUrl/$mascotaId/images/$imageId/principal'),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['message'] ?? 'No se pudo cambiar la foto principal',
      );
    }
  }

  static Future<void> eliminarFoto({
    required int mascotaId,
    required String imageId,
  }) async {
    final response = await AuthenticatedHttpClient.instance.delete(
      Uri.parse('$baseUrl/$mascotaId/images/$imageId'),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'No se pudo eliminar la foto');
    }
  }

  static Future<List<int>> descargarFoto(String url) async {
    final uri = Uri.parse(url.startsWith('http') ? url : '$originUrl$url');
    final response = await AuthenticatedHttpClient.instance.get(uri);
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').startsWith('image/')) {
      throw Exception('No se pudo validar la foto existente');
    }
    return response.bodyBytes;
  }

  static Future<void> guardarCambiosFotos({
    required int mascotaId,
    required List<String> originalImageIds,
    required List<String> retainedImageIds,
    required List<XFile> newImages,
    String? principalExistingId,
    int? principalNewIndex,
  }) async {
    final url = Uri.parse('$baseUrl/$mascotaId/images/batch');
    final response = await AuthenticatedHttpClient.instance.sendMultipart((
      token,
    ) async {
      final request = http.MultipartRequest('PUT', url);
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['original_image_ids'] = jsonEncode(originalImageIds);
      request.fields['retained_image_ids'] = jsonEncode(retainedImageIds);
      if (principalExistingId != null) {
        request.fields['principal_existing_id'] = principalExistingId;
      }
      if (principalNewIndex != null) {
        request.fields['principal_new_index'] = principalNewIndex.toString();
      }
      for (final image in newImages) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'imagenes',
            image.path,
            contentType: _imageContentType(image.name),
          ),
        );
      }
      return request;
    });
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['message'] ?? 'No se pudieron guardar los cambios');
    }
  }
}
