import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../auth/data/authenticated_http_client.dart';
import '../../auth/data/session_manager.dart';
import '../../pet/data/pet_image_selection.dart';

class ProfileException implements Exception {
  final String message;

  ProfileException(this.message);

  @override
  String toString() => message;
}

class ProfileService {
  static const String baseUrl = 'http://172.20.8.104:3000';

  static Future<Map<String, dynamic>> obtenerPerfil() async {
    final url = Uri.parse('$baseUrl/api/profile');

    final response = await AuthenticatedHttpClient.instance.get(url);

    final body = _decodeResponse(response);

    if (response.statusCode != 200 || body['ok'] != true) {
      throw ProfileException(
        body['message']?.toString() ?? 'Error consultando perfil del usuario',
      );
    }

    if (body['data'] is! Map) {
      throw ProfileException('El servidor devolvió un perfil inválido');
    }

    return Map<String, dynamic>.from(body['data']);
  }

  static Future<Map<String, dynamic>> actualizarPerfil({
    required String nombre,
    required String telefono,
  }) async {
    final url = Uri.parse('$baseUrl/api/profile');

    final response = await AuthenticatedHttpClient.instance.patch(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nombre': nombre, 'telefono': telefono}),
    );

    final body = _decodeResponse(response);

    if (response.statusCode != 200 || body['ok'] != true) {
      throw ProfileException(_extractErrorMessage(body));
    }

    if (body['data'] is! Map) {
      throw ProfileException('El servidor devolvió un perfil inválido');
    }

    return Map<String, dynamic>.from(body['data']);
  }

  static Future<Map<String, dynamic>> actualizarFotoPerfil(XFile image) async {
    final validationMessage = await validarFotoPerfil(image);
    if (validationMessage != null) {
      throw ProfileException(validationMessage);
    }

    final response = await AuthenticatedHttpClient.instance.sendMultipart((
      token,
    ) async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/profile/photo'),
      )..headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          image.path,
          contentType: _imageContentType(image.name),
        ),
      );
      return request;
    });
    final body = _decodeResponse(response);
    if (response.statusCode != 200 || body['ok'] != true) {
      throw ProfileException(_extractErrorMessage(body));
    }
    if (body['data'] is! Map) {
      throw ProfileException('El servidor devolvió un perfil inválido');
    }
    return Map<String, dynamic>.from(body['data']);
  }

  static Future<String?> validarFotoPerfil(XFile image) async {
    final validation = await validatePetImageSelection(
      selected: [image],
      alreadyAdded: const [],
      maxImages: 1,
    );
    if (validation.accepted.isEmpty) {
      return validation.rejectionMessage ??
          'Selecciona una imagen JPG, JPEG, PNG o WEBP de máximo 5 MB';
    }
    return null;
  }

  static http.MediaType _imageContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return http.MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.png')) return http.MediaType('image', 'png');
    if (lower.endsWith('.webp')) return http.MediaType('image', 'webp');
    throw ProfileException('Formato de imagen no soportado');
  }

  static Map<String, String> get imageHeaders {
    final token = SessionManager.instance.accessToken;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  static String? absolutePhotoUrl(dynamic value) {
    final path = value?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    return path.startsWith('http') ? path : 'http://172.20.8.104:3000$path';
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (!contentType.contains('application/json')) {
      return {
        'message':
            'El servidor respondió en un formato inesperado (HTTP ${response.statusCode}).',
      };
    }
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // La respuesta se convierte en un error controlado más abajo.
    }

    return {'message': 'No se pudo interpretar la respuesta del servidor'};
  }

  static String _extractErrorMessage(Map<String, dynamic> body) {
    final errors = body['errors'];

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

    return body['message']?.toString() ?? 'No se pudo actualizar el perfil';
  }
}
