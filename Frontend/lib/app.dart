import 'package:flutter/material.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/register_page.dart';
import 'features/pet/presentation/pages/register_pet_page.dart';
import 'features/pet/presentation/pages/my_pets_page.dart';
import 'features/map/presentation/pages/map_page.dart';

class AniMapApp extends StatelessWidget {
  const AniMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AniMap',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const MapPage(userName: 'Sebas',),
    );
  }
}