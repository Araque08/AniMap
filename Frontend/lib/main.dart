import 'package:flutter/material.dart';
import 'app.dart';
import 'config/api_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ApiConfig.initialize();
  runApp(const AniMapApp());
}
