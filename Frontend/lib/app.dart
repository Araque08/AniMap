import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'config/firebase_setup.dart';
import 'features/notifications/push_notification_coordinator.dart';
import 'features/report/data/reports_service.dart';
import 'features/sighting/presentation/pages/sightings_history_page.dart';
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
import 'features/report/presentation/pages/report_search_page.dart';
import 'features/sighting/presentation/pages/create_sighting_page.dart';
import 'features/admin/presentation/pages/home/admin_home_page.dart';

class AniMapApp extends StatefulWidget {
  final SessionManager? sessionManager;
  final FirebaseSetup? firebase;

  const AniMapApp({super.key, this.sessionManager, this.firebase});

  @override
  State<AniMapApp> createState() => _AniMapAppState();
}

class _AniMapAppState extends State<AniMapApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final SessionManager _sessionManager;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  PushNotificationCoordinator? _push;
  StreamSubscription<RemoteMessage>? _foregroundMessages, _openedMessages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionManager = widget.sessionManager ?? SessionManager.instance;
    if (widget.firebase case final firebase?) {
      _push = PushNotificationCoordinator(
        session: _sessionManager,
        loadReport: ReportsService.getOwnReportDetails,
        onOpen: (id, sightingId) {
          _messengerKey.currentState?.hideCurrentMaterialBanner();
          _navigatorKey.currentState?.push(
            MaterialPageRoute<void>(
              builder: (_) => SightingsHistoryPage(
                reportId: id,
                initialSightingId: sightingId,
              ),
            ),
          );
        },
        onForeground: (_, open) {
          final messenger = _messengerKey.currentState;
          messenger?.hideCurrentMaterialBanner();
          messenger?.showMaterialBanner(
            MaterialBanner(
              leading: const Icon(Icons.visibility, color: Color(0xFF2F9669)),
              content: const Text(
                'Registraron un nuevo avistamiento de tu mascota.',
              ),
              actions: [
                TextButton(onPressed: open, child: const Text('Ver')),
                TextButton(
                  onPressed: () => messenger.hideCurrentMaterialBanner(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
        },
        onUnavailable: () => _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'No fue posible abrir el reporte. Intenta nuevamente.',
            ),
          ),
        ),
      );
      _foregroundMessages = firebase.foregroundMessages.listen((message) async {
        final generation = _sessionManager.authenticatedSessionGeneration;
        final allowed = await firebase.notificationsAllowed();
        if (mounted &&
            generation == _sessionManager.authenticatedSessionGeneration) {
          _push?.foreground(message.data, allowed: allowed);
        }
      });
      _openedMessages = firebase.openedMessages.listen(
        (message) => _push?.tap(message.data),
      );
      _sessionManager.addListener(_hidePushWhenSignedOut);
    }
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

  void _hidePushWhenSignedOut() {
    if (!_sessionManager.isAuthenticated ||
        _sessionManager.authenticatedSessionGeneration == null) {
      _messengerKey.currentState?.hideCurrentMaterialBanner();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.firebase != null) {
      unawaited(widget.firebase!.registerMessaging());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionManager.removeListener(_hidePushWhenSignedOut);
    unawaited(_foregroundMessages?.cancel());
    unawaited(_openedMessages?.cancel());
    _push?.dispose();
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
      scaffoldMessengerKey: _messengerKey,
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
        '/search-reports': (context) => const ReportarBuscarPage(),
        '/create-lost-report': (context) => const CreateLostReportPage(),

        '/create-sighting': (context) {
          final arguments = ModalRoute.of(context)?.settings.arguments;

          return CreateSightingPage(
            reporteInicialId: arguments is int ? arguments : null,
          );
        },

        '/profile': (context) => const ProfilePage(),
        '/faqs': (context) => const FaqScreen(),
        '/pet-list': (context) => const MyPetsPage(),
      },
    );
  }
}
