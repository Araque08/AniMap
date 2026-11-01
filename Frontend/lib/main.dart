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
  final binding = FcmSessionBinding(sessionManager: SessionManager.instance);
  binding.start();
  final firebase = FirebaseSetup(onRegistration: binding.onRegistration);
  await firebase.initialize();
  runApp(const AniMapApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(firebase.registerMessaging());
  });
}
