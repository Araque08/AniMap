import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_manager.dart';

class FcmSessionBinding {
  FcmSessionBinding({required this.sessionManager, http.Client? client})
    : _client = client ?? http.Client();

  final SessionManager sessionManager;
  final http.Client _client;
  String? _registrationId;
  _Association? _bound;
  Future<void> _pending = Future<void>.value();
  bool _started = false;
  bool _disposed = false;

  Future<void> get pending => _pending;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    sessionManager.addListener(_queueSync);
    _queueSync();
  }

  void onRegistration(String registrationId) {
    if (_disposed || registrationId.trim().isEmpty) return;
    _registrationId = registrationId.trim();
    _queueSync();
  }

  void _queueSync() {
    if (_disposed) return;
    final generation = sessionManager.authenticatedSessionGeneration;
    final access = sessionManager.accessToken;
    final id = _registrationId;
    final desired = generation != null && access != null && id != null
        ? _Association(generation, access, id)
        : null;
    _pending = _pending.then((_) => _sync(desired)).catchError((_) {
      // Optional association failures must never fail login or logout.
    });
  }

  bool _isCurrent(_Association association) =>
      !_disposed &&
      sessionManager.authenticatedSessionGeneration == association.generation &&
      _registrationId == association.registrationId;

  Future<void> _sync(_Association? desired) async {
    if (_disposed || (desired != null && !_isCurrent(desired))) return;
    final previous = _bound;
    if (previous != null && !previous.sameTarget(desired)) {
      _bound = null;
      await _remove(previous);
    }
    if (desired == null || !_isCurrent(desired)) return;
    if (_bound?.sameTarget(desired) == true) {
      _bound = desired;
      return;
    }
    try {
      // Fixed credentials: never retry an old registration as the next user.
      final response = await _client
          .put(
            Uri.parse('${sessionManager.authBaseUrl}/fcm-registration'),
            headers: desired.headers,
            body: desired.body,
          )
          .timeout(const Duration(seconds: 10));
      if (_disposed) return;
      if (!_isCurrent(desired)) {
        await _remove(desired);
        return;
      }
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map &&
            body['ok'] == true &&
            body['data'] is Map &&
            body['data']['registered'] == true) {
          _bound = desired;
        }
      }
    } catch (_) {
      if (!_disposed && !_isCurrent(desired)) await _remove(desired);
      // Keep the current application session; try again on a later auth/FCM event.
    }
  }

  Future<void> _remove(_Association association) async {
    try {
      await _client
          .delete(
            Uri.parse('${sessionManager.authBaseUrl}/fcm-registration'),
            headers: association.headers,
            body: association.body,
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline logout still succeeds locally. Revoked/expired sessions are
      // ineligible for push; a later login atomically takes over the identifier.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    sessionManager.removeListener(_queueSync);
    _client.close();
  }
}

class _Association {
  const _Association(this.generation, this.accessToken, this.registrationId);
  final int generation;
  final String accessToken;
  final String registrationId;

  bool sameTarget(_Association? other) =>
      other != null &&
      generation == other.generation &&
      registrationId == other.registrationId;

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $accessToken',
  };
  String get body => jsonEncode({'registrationId': registrationId});
}
