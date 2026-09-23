import 'package:flutter/material.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/data/session_manager.dart';
import 'features/auth/presentation/session_gate.dart';
import 'features/faq/presentation/screens/faq_page.dart';
import 'features/pet/presentation/pages/register_pet_page.dart';
import 'features/pet/presentation/pages/my_pets_page.dart';
import 'features/pet/presentation/pages/pet_profile_page.dart';
import 'features/map/presentation/pages/map_page.dart';
import 'features/user/presentation/pages/profile_page.dart';
import 'features/report/presentation/pages/create_lost_report_page.dart';
import 'features/report/presentation/pages/report_type_selector_page.dart';
import 'features/sighting/presentation/pages/create_sighting_page.dart';
import 'features/admin/presentation/pages/admin_home_page.dart';

class AniMapApp extends StatefulWidget {
  final SessionManager? sessionManager;

  const AniMapApp({super.key, this.sessionManager});

  @override
  State<AniMapApp> createState() => _AniMapAppState();
}

class _AniMapAppState extends State<AniMapApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final SessionManager _sessionManager;

  @override
  void initState() {
    super.initState();
    _sessionManager = widget.sessionManager ?? SessionManager.instance;
    _sessionManager.onSessionInvalid = () {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (_) => false,
      );
    };
    _sessionManager.onRoleChanged = (role) {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        role == 'ADMINISTRADOR' ? '/admin' : '/home',
        (_) => false,
      );
    };
  }

  @override
  void dispose() {
    if (_sessionManager.onSessionInvalid != null) {
      _sessionManager.onSessionInvalid = null;
    }
    _sessionManager.onRoleChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'AniMap',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: SessionGate(sessionManager: _sessionManager),

      routes: {
        '/pet-profile': (context) => const PetProfilePage(mascotaId: 1),
        '/register-pet': (context) => const RegisterPetPage(),
        '/login': (context) => const LoginPage(),
        '/admin': (context) => _sessionManager.role == 'ADMINISTRADOR'
            ? AdminHomePage(sessionManager: _sessionManager)
            : _sessionManager.role == 'USUARIO'
            ? const MapPage()
            : const LoginPage(),
        '/home': (context) {
          final name = ModalRoute.of(context)?.settings.arguments as String?;
          return MapPage(userName: name ?? '');
        },
        '/create-report': (context) => const ReportTypeSelectorPage(),
        '/create-lost-report': (context) => const CreateLostReportPage(),
        '/create-sighting': (context) => const CreateSightingPage(),
        '/profile': (context) => const ProfilePage(),
        '/faqs': (context) => const FaqScreen(),
        '/pet-list': (context) => const MyPetsPage(),
      },
    );
  }
}
