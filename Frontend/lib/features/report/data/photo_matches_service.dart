import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import '../../auth/data/authenticated_http_client.dart';

class PhotoMatchesException implements Exception {
  const PhotoMatchesException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PhotoMatch {
  const PhotoMatch({
    required this.id,
    required this.similarity,
    required this.data,
  });
  final int id;
  final double similarity;
  final Map<String, dynamic> data;
  String get petName => (data['pet'] as Map?)?['name']?.toString() ?? 'Mascota';
  String get percentage => '${(similarity * 100).toStringAsFixed(1)} %';
  factory PhotoMatch.fromJson(Map<String, dynamic> data) {
    final id = int.tryParse(data['id'].toString());
    final score = num.tryParse(data['similarity'].toString())?.toDouble();
    if (id == null ||
        id <= 0 ||
        score == null ||
        !score.isFinite ||
        score < 0 ||
        score > 1) {
      throw const PhotoMatchesException('Respuesta de coincidencia inválida.');
    }
    return PhotoMatch(id: id, similarity: score, data: data);
  }
}

class PhotoMatchesService {
  PhotoMatchesService({AuthenticatedHttpClient? client})
    : _client = client ?? AuthenticatedHttpClient.instance;
  final AuthenticatedHttpClient _client;
  String get _base => '${ApiConfig.current.baseUrl}/recognition/matches';
  Future<List<PhotoMatch>> list({int? before}) async {
    final uri = Uri.parse(
      _base,
    ).replace(queryParameters: before == null ? null : {'before': '$before'});
    final data = _decode(await _client.get(uri));
    if (data is! List) throw const PhotoMatchesException('Historial inválido.');
    return data
        .map(
          (item) => PhotoMatch.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<PhotoMatch> detail(int id) async {
    final data = _decode(await _client.get(Uri.parse('$_base/$id')));
    if (data is! Map) {
      throw const PhotoMatchesException('Coincidencia no disponible.');
    }
    return PhotoMatch.fromJson(Map<String, dynamic>.from(data));
  }

  // The server authorizes every image request. Never follow a URL from a push
  // payload or cache private photographs in Image.network.
  Future<Uint8List> image(int id) async {
    final response = await _client.get(Uri.parse('$_base/$id/image'));
    if (response.statusCode != 200) {
      throw const PhotoMatchesException('Fotografía no disponible.');
    }
    return response.bodyBytes;
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode != 200) {
      throw PhotoMatchesException(
        response.statusCode == 503
            ? 'Las coincidencias fotográficas aún no están disponibles.'
            : 'No se pudo consultar la coincidencia. Intenta nuevamente.',
      );
    }
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['ok'] == true) return body['data'];
    } catch (_) {
      /* Use a neutral error: no private server diagnostics. */
    }
    throw const PhotoMatchesException('Respuesta inválida del servidor.');
  }
}
