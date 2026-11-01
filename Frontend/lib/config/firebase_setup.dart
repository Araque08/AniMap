import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class FirebaseSetup {
  FirebaseSetup({
    bool? isAndroid,
    Future<void> Function()? initializeFirebase,
    FirebaseMessaging Function()? messaging,
    this.onRegistration,
  }) : _isAndroid =
           isAndroid ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       _initializeFirebase = initializeFirebase ?? _initializeDefaultApp,
       _messaging = messaging ?? (() => FirebaseMessaging.instance);

  final bool _isAndroid;
  final Future<void> Function() _initializeFirebase;
  final FirebaseMessaging Function() _messaging;
  final ValueChanged<String>? onRegistration;
  StreamSubscription<String>? _registration;
  bool _initialized = false;
  bool _registrationAttempted = false;

  static Future<void> _initializeDefaultApp() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Future<bool> initialize() async {
    if (!_isAndroid) return false;
    if (_initialized) return true;
    try {
      await _initializeFirebase();
      _initialized = true;
      _log('Firebase Android: initialized.');
      return true;
    } catch (_) {
      _log('Firebase Android: initialization unavailable.');
      return false;
    }
  }

  Future<void> registerMessaging() async {
    if (!_initialized || _registrationAttempted) return;
    _registrationAttempted = true;
    try {
      final messaging = _messaging();
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        _log('FCM Android: notification permission not granted.');
        return;
      }
      _registration = messaging.onRegistered.listen((installationId) {
        if (installationId.isNotEmpty) {
          onRegistration?.call(installationId);
          _log('FCM Android: registration ready.');
        }
      }, onError: (_) => _log('FCM Android: registration unavailable.'));
      await messaging.register();
    } catch (_) {
      _log('FCM Android: registration unavailable.');
    }
  }

  Future<void> dispose() async {
    await _registration?.cancel();
    _registration = null;
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}
