import 'dart:convert';

import '../../auth/data/authenticated_http_client.dart';

const outsideAllowedAreaMessage =
    'Esta ubicación está fuera de Ciudad Salitre Occidental. AniMap actualmente '
    'permite registrar pérdidas y avistamientos únicamente dentro de la zona piloto.';

const outsideAllowedAreaWarningMessage =
    'Esta ubicación está fuera de Ciudad Salitre Occidental.\n'
    'Modo de pruebas activo: puedes continuar.';

const geofenceNetworkErrorMessage =
    'No pudimos validar si la ubicación está dentro de la zona permitida. '
    'Inténtalo nuevamente.';

class GeofenceException implements Exception {
  const GeofenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeofenceCheckResult {
  const GeofenceCheckResult({
    required this.inside,
    required this.allowed,
    required this.mode,
    required this.areaName,
  });

  final bool inside;
  final bool allowed;
  final String mode;
  final String areaName;
}

class GeofenceService {
  static const _url = 'http://192.168.0.6:3000/api/geofence/check';

  static Future<GeofenceCheckResult> check(double lat, double lng) async {
    try {
      final response = await AuthenticatedHttpClient.instance.post(
        Uri.parse(_url),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'lat': lat, 'lng': lng}),
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded is! Map) {
        throw const GeofenceException(geofenceNetworkErrorMessage);
      }
      final area = decoded['area'] is Map
          ? Map<String, dynamic>.from(decoded['area'] as Map)
          : const <String, dynamic>{};
      if (decoded['inside'] is! bool ||
          decoded['allowed'] is! bool ||
          (decoded['mode'] != 'WARN' && decoded['mode'] != 'ENFORCE')) {
        throw const GeofenceException(geofenceNetworkErrorMessage);
      }
      return GeofenceCheckResult(
        inside: decoded['inside'] as bool,
        allowed: decoded['allowed'] as bool,
        mode: decoded['mode'] as String,
        areaName: area['name']?.toString() ?? 'Salitre Occidental',
      );
    } on GeofenceException {
      rethrow;
    } catch (_) {
      throw const GeofenceException(geofenceNetworkErrorMessage);
    }
  }
}

enum GeofenceValidationState {
  idle,
  checking,
  inside,
  outsideWarning,
  outsideBlocked,
  networkError,
}

GeofenceValidationState geofenceStateFor(GeofenceCheckResult result) {
  if (result.inside) return GeofenceValidationState.inside;
  return result.allowed
      ? GeofenceValidationState.outsideWarning
      : GeofenceValidationState.outsideBlocked;
}

bool geofenceStateAllowsSubmit(GeofenceValidationState state) =>
    state == GeofenceValidationState.inside ||
    state == GeofenceValidationState.outsideWarning;
