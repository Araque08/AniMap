import 'package:flutter/material.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/register_page.dart';
import 'features/faq/presentation/screens/faq_page.dart';
import 'features/pet/presentation/pages/register_pet_page.dart';
import 'features/pet/presentation/pages/my_pets_page.dart';
import 'features/map/presentation/pages/map_page.dart';
import 'features/user/presentation/pages/profile_page.dart';
import 'features/report/presentation/pages/create_lost_report_page.dart';

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

      initialRoute: '/home',
      routes: {
        '/home': (context) => const MapPage(userName: 'Sebas'),
        '/create-report': (context) => const CreateLostReportPage(),
        '/profile': (context) => const ProfilePage(),
        '/faqs': (context) => const FaqScreen(),
        '/pet-list': (context) => const MyPetsPage(),
      },
    );
  }
}