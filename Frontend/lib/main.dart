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
  late final FirebaseSetup firebase;
  final binding = FcmSessionBinding(
    sessionManager: SessionManager.instance,
    onAuthenticated: () => firebase.registerMessaging(),
    onLogout: () => firebase.unregisterMessaging(),
  );
  firebase = FirebaseSetup(onRegistration: binding.onRegistration);
  await firebase.initialize();
  binding.start();
  runApp(AniMapApp(firebase: firebase));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(firebase.startMessageHandling());
    unawaited(firebase.registerMessaging());
  });
}
