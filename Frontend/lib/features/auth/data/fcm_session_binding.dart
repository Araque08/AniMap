import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_manager.dart';

class FcmSessionBinding {
  FcmSessionBinding({
    required this.sessionManager,
    http.Client? client,
    this.onAuthenticated,
    this.onLogout,
  }) : _client = client ?? http.Client();

  final SessionManager sessionManager;
  final http.Client _client;
  final Future<void> Function()? onAuthenticated;
  final Future<void> Function()? onLogout;
  int _logoutGeneration = 0;
  int? _lastGeneration;
  String? _registrationId;
  _Association? _bound;
  Future<void> _pending = Future<void>.value();
  bool _started = false;
  bool _disposed = false;

  Future<void> get pending => _pending;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _logoutGeneration = sessionManager.logoutGeneration;
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
    final loggedOut = _logoutGeneration != sessionManager.logoutGeneration;
    if (loggedOut) {
      _logoutGeneration = sessionManager.logoutGeneration;
      _registrationId = null;
      if (onLogout != null) unawaited(onLogout!().catchError((_) {}));
    }
    if (generation != null &&
        generation != _lastGeneration &&
        onAuthenticated != null) {
      unawaited(onAuthenticated!().catchError((_) {}));
    }
    _lastGeneration = generation;
    final access = sessionManager.accessToken;
    final id = _registrationId;
    final desired = generation != null && access != null && id != null
        ? _Association(generation, access, id, _logoutGeneration)
        : null;
    _pending = _pending.then((_) => _sync(desired, loggedOut)).catchError((_) {
      // Optional association failures must never fail login or logout.
    });
  }

  bool _isCurrent(_Association association) =>
      !_disposed &&
      sessionManager.authenticatedSessionGeneration == association.generation &&
      _registrationId == association.registrationId;

  Future<void> _sync(_Association? desired, bool loggedOut) async {
    if (_disposed || (desired != null && !_isCurrent(desired))) return;
    final previous = _bound;
    if (previous != null &&
        (loggedOut || desired != null) &&
        !previous.sameTarget(desired)) {
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
        if (_wasReplaced(desired)) {
          await _remove(desired);
        } else if (response.statusCode == 200) {
          _bound = desired;
        }
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
      if (!_disposed && !_isCurrent(desired) && _wasReplaced(desired)) {
        await _remove(desired);
      }
      // Keep the current application session; try again on a later auth/FCM event.
    }
  }

  bool _wasReplaced(_Association association) =>
      sessionManager.logoutGeneration != association.logoutGeneration ||
      sessionManager.authenticatedSessionGeneration != null;

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
      // Offline logout also unregisters the SDK. Server logout and the next
      // registration independently revoke/transfer the persistent association.
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
  const _Association(
    this.generation,
    this.accessToken,
    this.registrationId,
    this.logoutGeneration,
  );
  final int generation;
  final String accessToken;
  final String registrationId;
  final int logoutGeneration;

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
