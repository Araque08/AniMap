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
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  final _foreground = StreamController<RemoteMessage>.broadcast();
  final _opened = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get foregroundMessages => _foreground.stream;
  Stream<RemoteMessage> get openedMessages => _opened.stream;
  Future<void> _sdkTail = Future<void>.value();
  int _epoch = 0;
  bool _disposed = false;
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
    if (!_initialized || _registrationAttempted || _disposed) return;
    _registrationAttempted = true;
    final epoch = _epoch;
    _sdkTail = _sdkTail.then((_) => _register(epoch));
    await _sdkTail;
  }

  Future<void> _register(int epoch) async {
    if (_disposed || epoch != _epoch) return;
    try {
      final messaging = _messaging();
      final settings = await messaging.requestPermission();
      if (_disposed || epoch != _epoch) return;
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        _registrationAttempted = false;
        _log('FCM Android: notification permission not granted.');
        return;
      }
      await _registration?.cancel();
      _registration = messaging.onRegistered.listen((installationId) {
        if (!_disposed && epoch == _epoch && installationId.isNotEmpty) {
          onRegistration?.call(installationId);
          _log('FCM Android: registration ready.');
        }
      }, onError: (_) => _log('FCM Android: registration unavailable.'));
      await messaging.register();
    } catch (_) {
      if (epoch == _epoch) _registrationAttempted = false;
      _log('FCM Android: registration unavailable.');
    }
  }

  Future<void> unregisterMessaging() async {
    if (!_initialized || _disposed) return;
    _epoch++;
    _registrationAttempted = false;
    _sdkTail = _sdkTail.then((_) async {
      await _registration?.cancel();
      _registration = null;
      try {
        await _messaging().unregister();
      } catch (_) {
        _log('FCM Android: unregister unavailable.');
      }
    });
    await _sdkTail;
  }

  // Subscribe after the app has its navigator and message listeners in place.
  Future<void> startMessageHandling({
    Stream<RemoteMessage>? foreground,
    Stream<RemoteMessage>? opened,
    Future<RemoteMessage?> Function()? initialMessage,
  }) async {
    if (!_initialized || _disposed || _foregroundSubscription != null) return;
    _foregroundSubscription = (foreground ?? FirebaseMessaging.onMessage)
        .listen(
          _foreground.add,
          onError: (_) => _log('FCM Android: message unavailable.'),
        );
    _openedSubscription = (opened ?? FirebaseMessaging.onMessageOpenedApp)
        .listen(
          _opened.add,
          onError: (_) => _log('FCM Android: message unavailable.'),
        );
    try {
      final initial =
          await (initialMessage ?? _messaging().getInitialMessage)();
      if (!_disposed && initial != null) _opened.add(initial);
    } catch (_) {
      _log('FCM Android: initial message unavailable.');
    }
  }

  Future<bool> notificationsAllowed() async {
    if (!_initialized || _disposed) return false;
    try {
      return (await _messaging().getNotificationSettings())
              .authorizationStatus ==
          AuthorizationStatus.authorized;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    await _registration?.cancel();
    _registration = null;
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _foreground.close();
    await _opened.close();
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}
