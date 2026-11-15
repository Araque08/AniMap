import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'config/api_config.dart';
import 'config/firebase_setup.dart';
import 'features/auth/data/fcm_session_binding.dart';
import 'features/auth/data/session_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiConfig.initialize();

  // Conservar el ciclo de registro y revocación FCM implementado en dev.
  late final FirebaseSetup firebase;
  final binding = FcmSessionBinding(
    sessionManager: SessionManager.instance,
    onAuthenticated: () => firebase.registerMessaging(),
    onLogout: () => firebase.unregisterMessaging(),
  );

  firebase = FirebaseSetup(onRegistration: binding.onRegistration);
  await firebase.initialize();
  binding.start();

  // app.dart gestiona los avisos en primer plano y la navegación de HU-016/HU-064.
  // Evitar un segundo listener directo de FirebaseMessaging.onMessage aquí.
  runApp(AniMapApp(firebase: firebase));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(firebase.startMessageHandling());
    unawaited(firebase.registerMessaging());
  });
}
