import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../config/api_config.dart';
import '../../auth/data/authenticated_http_client.dart';
import '../../auth/data/session_manager.dart';

class RecognitionException implements Exception {
  const RecognitionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImageMatch {
  const ImageMatch({
    required this.reportId,
    required this.name,
    required this.species,
    required this.similarity,
    required this.imageUrl,
  });
  final int reportId;
  final String name, species, imageUrl;
  final double similarity;
}

class RecognitionResults {
  const RecognitionResults({
    required this.matches,
    required this.threshold,
    this.searchedImages = 0,
    this.skippedImages = 0,
  });
  final List<ImageMatch> matches;
  final double threshold;
  final int searchedImages, skippedImages;
}

class ImageRecognitionService {
  ImageRecognitionService({
    SessionManager? sessionManager,
    http.Client Function()? clientFactory,
  }) : _session = sessionManager ?? SessionManager.instance,
       _clientFactory = clientFactory ?? http.Client.new;
  final SessionManager _session;
  final http.Client Function() _clientFactory;
  http.Client? _active;
  bool _disposed = false;

  Future<RecognitionResults> search(XFile photo) async {
    if (_disposed) throw const RecognitionException('La búsqueda se canceló.');
    if (await photo.length() > 5 * 1024 * 1024) {
      throw const RecognitionException(
        'La fotografía debe pesar máximo 5 MiB.',
      );
    }
    final bytes = await photo.readAsBytes();
    if (_disposed) throw const RecognitionException('La búsqueda se canceló.');
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const RecognitionException(
        'La fotografía está vacía o supera 5 MiB.',
      );
    }
    final subtype =
        bytes.length >= 3 &&
            bytes[0] == 255 &&
            bytes[1] == 216 &&
            bytes[2] == 255
        ? 'jpeg'
        : bytes.length >= 8 &&
              bytes.take(8).join(',') == '137,80,78,71,13,10,26,10'
        ? 'png'
        : bytes.length >= 12 &&
              ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
              ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
        ? 'webp'
        : null;
    if (subtype == null) {
      throw const RecognitionException(
        'Selecciona una imagen JPG, JPEG, PNG o WEBP.',
      );
    }
    final client = _clientFactory();
    _active = client;
    try {
      final response =
          await AuthenticatedHttpClient(
                sessionManager: _session,
                client: client,
              )
              .sendMultipart((token) async {
                final request = http.MultipartRequest(
                  'POST',
                  Uri.parse('${ApiConfig.current.baseUrl}/recognition/search'),
                );
                request.headers['Authorization'] = 'Bearer $token';
                request.files.add(
                  http.MultipartFile.fromBytes(
                    'foto',
                    bytes,
                    filename: 'consulta.$subtype',
                    contentType: http.MediaType('image', subtype),
                  ),
                );
                return request;
              })
              .timeout(const Duration(seconds: 130));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 || body is! Map || body['ok'] != true) {
        final messages = {
          400: 'No se pudo leer la fotografía. Selecciona otra.',
          413: 'La fotografía debe pesar máximo 5 MiB.',
          429: 'Hay otra búsqueda en curso. Intenta en unos segundos.',
          504: 'La búsqueda tardó demasiado. Intenta nuevamente.',
        };
        throw RecognitionException(
          messages[response.statusCode] ??
              'No fue posible realizar la búsqueda. Intenta nuevamente.',
        );
      }
      final raw = body['matches'];
      final threshold = body['threshold'];
      if (raw is! List ||
          threshold is! num ||
          !threshold.isFinite ||
          threshold < 0 ||
          threshold > 1) {
        throw const FormatException();
      }
      final matches = raw.map((item) {
        final id = item['reportId'], score = item['similarity'];
        if (id is! int ||
            id <= 0 ||
            score is! num ||
            !score.isFinite ||
            score < threshold ||
            score > 1) {
          throw const FormatException();
        }
        return ImageMatch(
          reportId: id,
          name: item['pet']['nombre'] as String,
          species: item['pet']['especie'] as String,
          similarity: score.toDouble(),
          imageUrl: ApiConfig.current.resolveUrl(
            item['photo']['url'] as String,
          ),
        );
      }).toList();
      return RecognitionResults(
        matches: matches,
        threshold: threshold.toDouble(),
        searchedImages: (body['searchedImages'] as num?)?.toInt() ?? 0,
        skippedImages: (body['skippedImages'] as num?)?.toInt() ?? 0,
      );
    } on RecognitionException {
      rethrow;
    } catch (_) {
      throw const RecognitionException(
        'No fue posible realizar la búsqueda. Revisa tu conexión e intenta nuevamente.',
      );
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  void dispose() {
    _disposed = true;
    _active?.close();
  }
}
