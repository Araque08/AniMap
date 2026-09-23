import 'dart:convert';

import '../../auth/data/authenticated_http_client.dart';

class GeocodingException implements Exception {
  const GeocodingException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class GeocodingCandidate {
  const GeocodingCandidate({
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    required this.placeId,
    required this.locationType,
    required this.inside,
    required this.allowed,
  });

  final String formattedAddress;
  final double lat;
  final double lng;
  final String placeId;
  final String locationType;
  final bool inside;
  final bool allowed;

  factory GeocodingCandidate.fromJson(Map<String, dynamic> json) {
    final lat = json['lat'];
    final lng = json['lng'];
    if (json['formattedAddress'] is! String ||
        json['placeId'] is! String ||
        json['locationType'] is! String ||
        lat is! num ||
        lng is! num ||
        json['inside'] is! bool ||
        json['allowed'] is! bool) {
      throw const GeocodingException(
        'INVALID_GEOCODING_RESPONSE',
        'El servidor devolvió una dirección inválida.',
      );
    }
    return GeocodingCandidate(
      formattedAddress: json['formattedAddress'] as String,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      placeId: json['placeId'] as String,
      locationType: json['locationType'] as String,
      inside: json['inside'] as bool,
      allowed: json['allowed'] as bool,
    );
  }
}

class GeocodingResult {
  const GeocodingResult({required this.mode, required this.candidates});

  final String mode;
  final List<GeocodingCandidate> candidates;
}

class AddressLocationSelection {
  const AddressLocationSelection({
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    required this.placeId,
    required this.inside,
    required this.allowed,
    required this.mode,
  });

  final String formattedAddress;
  final double lat;
  final double lng;
  final String placeId;
  final bool inside;
  final bool allowed;
  final String mode;
}

class GeocodingService {
  static const _url = 'http://172.20.8.104:3000/api/geocoding/address';

  static Future<GeocodingResult> geocode(String address) async {
    final response = await AuthenticatedHttpClient.instance.post(
      Uri.parse(_url),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'address': address.trim()}),
    );
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
    } catch (_) {
      throw const GeocodingException(
        'INVALID_GEOCODING_RESPONSE',
        'No se pudo interpretar la respuesta del servidor.',
      );
    }
    if (response.statusCode != 200 || body['ok'] != true) {
      throw GeocodingException(
        body['code']?.toString() ?? 'GEOCODING_UNAVAILABLE',
        body['message']?.toString() ??
            'No pudimos validar la dirección en este momento. Inténtalo nuevamente.',
      );
    }
    final rawCandidates = body['candidates'];
    final mode = body['mode'];
    if (rawCandidates is! List || (mode != 'WARN' && mode != 'ENFORCE')) {
      throw const GeocodingException(
        'INVALID_GEOCODING_RESPONSE',
        'El servidor devolvió una respuesta de dirección inválida.',
      );
    }
    try {
      return GeocodingResult(
        mode: mode as String,
        candidates: rawCandidates
            .map(
              (item) => GeocodingCandidate.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
    } on GeocodingException {
      rethrow;
    } catch (_) {
      throw const GeocodingException(
        'INVALID_GEOCODING_RESPONSE',
        'El servidor devolvió una respuesta de dirección inválida.',
      );
    }
  }
}
