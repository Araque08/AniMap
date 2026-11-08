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
import 'package:flutter/services.dart';
import 'features/pet/data/pets_service.dart';
import 'features/report/data/device_location_service.dart';
import 'features/report/data/geofence_service.dart';

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
  static const MethodChannel _emergencyChannel =
  MethodChannel('animap/emergency_shortcut');

  bool _mostrandoConfirmacion = false;
  bool _procesandoReporteRapido = false;



  Future<void> _probarUbicacionEmergencia(
      Map<String, dynamic> mascota,
      ) async {
    final messenger = _messengerKey.currentState;

    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'AniMap está preparando tu reporte de emergencia...',
        ),
        duration: Duration(seconds: 20),
      ),
    );

    try {
      final generacionSesion =
          _sessionManager.authenticatedSessionGeneration;

      if (generacionSesion == null ||
          _sessionManager.role != 'USUARIO') {
        throw Exception('Debes iniciar sesión como usuario.');
      }

      final mascotaId = int.tryParse(
        mascota['id']?.toString() ?? '',
      );

      if (mascotaId == null || mascotaId <= 0) {
        throw Exception('La mascota seleccionada no es válida.');
      }

      // 1. Verificar nuevamente las mascotas disponibles
      // utilizando el servicio de reportes existente.
      final mascotas = await ReportsService.getReportablePets();

      final disponible = mascotas.any((item) {
        final id = int.tryParse(item['id']?.toString() ?? '');
        final estado =
            item['estado']?.toString().toUpperCase() ?? '';

        return id == mascotaId &&
            estado == 'ACTIVA' &&
            item['tieneReporteActivo'] != true;
      });

      if (!disponible) {
        throw Exception(
          'Esta mascota ya no está disponible para '
              'crear un reporte de pérdida.',
        );
      }

      // 2. Solicitar la ubicación actual del celular.
      final ubicacion =
      await DeviceLocationService.getCurrentLocation();

      if (!mounted) return;

      // 3. Validar la zona geográfica.
      final validacion = await GeofenceService.check(
        ubicacion.latitude,
        ubicacion.longitude,
      );

      if (!validacion.allowed) {
        throw Exception(
          'La ubicación está fuera de la zona '
              'permitida para registrar reportes.',
        );
      }

      // Evitar el envío si la sesión cambió durante
      // las operaciones anteriores.
      if (!mounted ||
          generacionSesion !=
              _sessionManager.authenticatedSessionGeneration) {
        return;
      }

      // 4. Preparar la información del reporte.
      final datosUbicacion = <String, dynamic>{
        'metodo': 'GPS',
        'lat': ubicacion.latitude,
        'lng': ubicacion.longitude,
        'precisionM': ubicacion.accuracy,
        'direccion': null,
        'placeId': null,
      };

      // 5. Crear el reporte en PostgreSQL
      // mediante el backend existente de AniMap.

      final nombreMascota =
          mascota['nombre']?.toString().trim() ?? '';

      final nombreParaReporte = nombreMascota.isNotEmpty
          ? nombreMascota
          : 'esta mascota';

      await ReportsService.createReport(
        mascotaId: mascotaId,
        descripcion:
        '¡Ayúdanos a encontrar a $nombreParaReporte! '
            'Se perdió cerca de la ubicación señalada en el mapa. '
            'Si la has visto o tienes información sobre su paradero, '
            'por favor registra un avistamiento en AniMap. '
            '¡Cualquier información puede ser de gran ayuda '
            'para encontrarla!',
        mostrarContacto: false,
        ubicacion: datosUbicacion,
      );


      if (!mounted) return;

      // 6. Confirmar la creación.
      final nombre =
          mascota['nombre']?.toString() ?? 'Tu mascota';

      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            backgroundColor: const Color(0xFF21865B),
            content: Text(
              'Reporte de pérdida de $nombre '
                  'creado correctamente.',
            ),
          ),
        );

      debugPrint(
        'AniMap: reporte rápido creado '
            'para mascota $mascotaId',
      );
    } catch (error) {
      if (!mounted) return;

      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            backgroundColor: Colors.red.shade700,
            content: Text(
              'No se pudo crear el reporte rápido: $error',
            ),
          ),
        );
    }
  }



  Future<void> _iniciarReporteRapido() async {
    if (!mounted) return;

    if (!_sessionManager.isAuthenticated ||
        _sessionManager.role != 'USUARIO') {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Debes iniciar sesión para reportar una mascota.',
          ),
        ),
      );
      return;
    }

    try {
      // Consultar las mascotas registradas del usuario.
      final mascotas = await PetsService.getMyPets();

      if (!mounted) return;

      // Solamente mascotas que pueden reportarse.
      final disponibles = mascotas.where((mascota) {
        final estado =
            mascota['estado']?.toString().toUpperCase() ?? '';

        return estado == 'ACTIVA';
      }).toList();

      if (disponibles.isEmpty) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'No tienes mascotas disponibles para reportar.',
            ),
          ),
        );
        return;
      }

      if (disponibles.length == 1) {
        await _probarUbicacionEmergencia(disponibles.first);
        return;
      }

      // Si tiene varias mascotas, permitir elegir una.
      final contexto = _navigatorKey.currentContext;

      if (contexto == null) return;

      final seleccionada = await showDialog<Map<String, dynamic>>(
        context: contexto,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('¿Cuál mascota se perdió?'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: disponibles.map((mascota) {
                  return ListTile(
                    leading: const Icon(
                      Icons.pets,
                      color: Color(0xFF21986A),
                    ),
                    title: Text(
                      mascota['nombre']?.toString() ?? 'Sin nombre',
                    ),
                    subtitle: Text(
                      mascota['especie']?.toString() ?? '',
                    ),
                    onTap: () {
                      Navigator.pop(dialogContext, mascota);
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      );

      if (!mounted || seleccionada == null) return;

      await _probarUbicacionEmergencia(seleccionada);
      return;

      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            'Mascota seleccionada: ${seleccionada['nombre']}',
          ),
        ),
      );

      // Después conectaremos la ubicación y el backend.
    } catch (error) {
      if (!mounted) return;

      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudieron consultar tus mascotas.',
          ),
        ),
      );
    }
  }


  @override
  void initState() {
    super.initState();
    _emergencyChannel.setMethodCallHandler((call) async {
      if (call.method != 'emergencyShortcutActivated') return;

      if (_procesandoReporteRapido) return;

      _procesandoReporteRapido = true;

      try {
        await _iniciarReporteRapido();
      } finally {
        _procesandoReporteRapido = false;
      }
    });
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


  Future<void> _mostrarConfirmacionReporteRapido() async {
    // Evitar abrir varias ventanas simultáneamente.
    if (!mounted || _mostrandoConfirmacion) return;

    final navigator = _navigatorKey.currentState;
    final contexto = _navigatorKey.currentContext;

    if (navigator == null || contexto == null) return;

    _mostrandoConfirmacion = true;

    try {
      // Solo usuarios autenticados pueden reportar.
      if (!_sessionManager.isAuthenticated ||
          _sessionManager.role != 'USUARIO') {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Debes iniciar sesión como usuario '
                  'para utilizar el reporte rápido.',
            ),
          ),
        );
        return;
      }

      final confirmado = await showDialog<bool>(
        context: contexto,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.pets,
                  color: Color(0xFF21986A),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Reporte rápido AniMap'),
                ),
              ],
            ),
            content: const Text(
              'Detectamos la combinación de botones '
                  'de volumen.\n\n'
                  '¿Quieres continuar con el reporte '
                  'rápido de una mascota perdida?\n\n'
                  'Por ahora no se creará ningún reporte '
                  'automáticamente.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF21986A),
                ),
                child: const Text('Continuar'),
              ),
            ],
          );
        },
      );

      if (!mounted || confirmado != true) return;

      // Prueba del flujo: abrir el formulario existente.
      // Todavía no enviamos información al backend.
      _navigatorKey.currentState?.pushNamed(
        '/create-lost-report',
      );
    } finally {
      _mostrandoConfirmacion = false;
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
    _emergencyChannel.setMethodCallHandler(null);
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
