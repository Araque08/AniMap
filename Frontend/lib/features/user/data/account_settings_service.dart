import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/data/authenticated_http_client.dart';

class AccountSettingsException implements Exception {
  const AccountSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NotificationPreferencesData {
  const NotificationPreferencesData({
    required this.notificationsEnabled,
    required this.onlyMyZone,
    required this.species,
    required this.eventType,
    required this.radiusKm,
  });

  final bool notificationsEnabled;
  final bool onlyMyZone;
  final String? species;
  final String? eventType;
  final int radiusKm;

  factory NotificationPreferencesData.fromJson(Map<String, dynamic> json) {
    return NotificationPreferencesData(
      notificationsEnabled: json['notificacionesActivas'] == true,
      onlyMyZone: json['soloMiZona'] == true,
      species: json['especieFiltro']?.toString(),
      eventType: json['tipoEvento']?.toString(),
      radiusKm: (json['radioKm'] as num?)?.round() ?? 2,
    );
  }

  Map<String, dynamic> toJson() => {
    'notificacionesActivas': notificationsEnabled,
    'soloMiZona': onlyMyZone,
    'especieFiltro': species,
    'tipoEvento': eventType,
    'radioKm': radiusKm,
  };

  bool hasSameValues(NotificationPreferencesData other) {
    return notificationsEnabled == other.notificationsEnabled &&
        onlyMyZone == other.onlyMyZone &&
        species == other.species &&
        eventType == other.eventType &&
        radiusKm == other.radiusKm;
  }
}

class ActiveSessionData {
  const ActiveSessionData({
    required this.id,
    required this.deviceId,
    required this.createdAt,
    required this.expiresAt,
    required this.isCurrent,
  });

  final int id;
  final String deviceId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isCurrent;

  factory ActiveSessionData.fromJson(Map<String, dynamic> json) {
    return ActiveSessionData(
      id: (json['id'] as num).toInt(),
      deviceId: json['deviceId']?.toString() ?? 'Dispositivo',
      createdAt: DateTime.parse(json['creadoEn'].toString()),
      expiresAt: DateTime.parse(json['expiraEn'].toString()),
      isCurrent: json['isCurrent'] == true,
    );
  }
}

class AccountSettingsService {
  static const String _baseUrl = 'http://10.0.2.2:3000';

  static Future<NotificationPreferencesData> loadPreferences() async {
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$_baseUrl/api/notification-preferences'),
    );
    final body = _decode(response);
    _requireSuccess(response, body, expectedStatus: 200);
    return NotificationPreferencesData.fromJson(_dataMap(body));
  }

  static Future<NotificationPreferencesData> savePreferences(
    NotificationPreferencesData preferences,
  ) async {
    final response = await AuthenticatedHttpClient.instance.patch(
      Uri.parse('$_baseUrl/api/notification-preferences'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(preferences.toJson()),
    );
    final body = _decode(response);
    _requireSuccess(response, body, expectedStatus: 200);
    return NotificationPreferencesData.fromJson(_dataMap(body));
  }

  static Future<List<ActiveSessionData>> loadSessions() async {
    final response = await AuthenticatedHttpClient.instance.get(
      Uri.parse('$_baseUrl/api/auth/sessions'),
    );
    final body = _decode(response);
    _requireSuccess(response, body, expectedStatus: 200);
    final data = body['data'];
    if (data is! List) {
      throw const AccountSettingsException(
        'El servidor devolvió una lista de sesiones inválida.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => ActiveSessionData.fromJson(Map.from(item)))
        .toList();
  }

  static Future<void> revokeSession(int sessionId) async {
    final response = await AuthenticatedHttpClient.instance.post(
      Uri.parse('$_baseUrl/api/auth/sessions/$sessionId/revoke'),
    );
    final body = _decode(response);
    _requireSuccess(response, body, expectedStatus: 200);
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  static Map<String, dynamic> _dataMap(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const AccountSettingsException(
      'El servidor devolvió información incompleta.',
    );
  }

  static void _requireSuccess(
    http.Response response,
    Map<String, dynamic> body, {
    required int expectedStatus,
  }) {
    if (response.statusCode == expectedStatus && body['ok'] == true) return;
    throw AccountSettingsException(
      body['message']?.toString() ??
          'No fue posible completar la operación. Intenta nuevamente.',
    );
  }
}
