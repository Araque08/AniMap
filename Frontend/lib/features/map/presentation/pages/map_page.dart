import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../data/map_reports_client.dart';
import '../../../report/data/report_datetime.dart';
import '../../../report/data/device_location_service.dart';

typedef DeviceLocationLoader = Future<DeviceLocation> Function();

class MapPage extends StatefulWidget {
  final String userName;
  final DeviceLocationLoader? locationLoader;
  final MapReportsClient? reportsClient;

  const MapPage({
    super.key,
    this.userName = '',
    this.locationLoader,
    this.reportsClient,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

/* ============================================================================
   ENUMS DEL MAPA
   ============================================================================ */

enum MapFilter { active, found }

enum MapStatus { loaded, empty, error }

enum ReportType { lost, sighting, found }

Color markerColorForReportType(ReportType type) {
  switch (type) {
    case ReportType.lost:
      return const Color(0xFFE96F67);
    case ReportType.sighting:
      return const Color(0xFFF2A65A);
    case ReportType.found:
      return const Color(0xFF3F9568);
  }
}

/* ============================================================================
   MODELO PARA LOS REPORTES DEL MAPA
   ============================================================================ */

/*
  Este modelo representa los reportes que se muestran en el mapa.
  Esta información se construye desde la respuesta JSON que entrega
  el backend en /api/map/reports.
*/
class MapReport {
  final String id;
  final String title;
  final String petName;
  final String details;
  final String location;
  final String reference;
  final String description;
  final String dateText;
  final String createdDateText;
  final String closedDateText;
  final DateTime? occurredAt;
  final String? imageUrl;
  final List<String> imageUrls;
  final LatLng position;
  final ReportType type;
  final bool isLinked;
  final int? linkedReportId;

  /*
    Aquí guardo los datos de contacto del dueño.
    Estos datos solo se muestran cuando el backend indica que el dueño autorizó
    mostrar contacto mediante showContact.
  */
  final bool showContact;
  final bool isOwner;
  final String ownerName;
  final String ownerPhone;
  final String ownerEmail;

  const MapReport({
    required this.id,
    required this.title,
    required this.petName,
    required this.details,
    required this.location,
    required this.reference,
    required this.description,
    required this.dateText,
    this.createdDateText = '',
    this.closedDateText = '',
    required this.occurredAt,
    required this.imageUrl,
    this.imageUrls = const [],
    required this.position,
    required this.type,
    this.isLinked = false,
    this.linkedReportId,
    required this.showContact,
    required this.isOwner,
    required this.ownerName,
    required this.ownerPhone,
    required this.ownerEmail,
  });

  /*
    Aquí convierto cada registro que llega desde el backend en un MapReport.
    Esto permite que el mapa pinte datos reales de PostgreSQL sin cambiar
    la estructura visual que ya teníamos funcionando.
  */
  factory MapReport.fromJson(Map<String, dynamic> json) {
    final rawDate = json['dateText'];
    return MapReport(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Reporte',
      petName: json['petName']?.toString() ?? 'No identificado',
      details: json['details']?.toString() ?? '',
      location: json['location']?.toString() ?? 'Ubicación no disponible',
      reference: json['reference']?.toString() ?? '',
      description: json['description']?.toString() ?? 'Sin descripción',
      dateText: _formatDateText(rawDate),
      createdDateText: _formatDateText(json['createdDateText']),
      closedDateText: json['closedDateText'] == null
          ? ''
          : _formatDateText(json['closedDateText']),
      occurredAt: reportDateTimeInBogota(rawDate),
      imageUrl: _imageUrl(json['imageUrl']),
      imageUrls: _imageUrls(json['imageUrls'], json['imageUrl']),
      position: LatLng(_toDouble(json['lat']), _toDouble(json['lng'])),
      type: _parseReportType(json['type']),
      isLinked: json['isLinked'] == true,
      linkedReportId: int.tryParse(json['linkedReportId']?.toString() ?? ''),
      showContact: json['showContact'] == true,
      isOwner: json['isOwner'] == true,
      ownerName: json['ownerName']?.toString() ?? '',
      ownerPhone: json['ownerPhone']?.toString() ?? '',
      ownerEmail: json['ownerEmail']?.toString() ?? '',
    );
  }

  static String? _imageUrl(dynamic value) {
    final path = value?.toString();
    if (path == null || path.isEmpty) return null;
    return path.startsWith('http') ? path : 'http://10.0.2.2:3000$path';
  }

  static List<String> _imageUrls(dynamic values, dynamic principal) {
    final urls = <String>[];
    final principalUrl = _imageUrl(principal);
    if (principalUrl != null) urls.add(principalUrl);
    if (values is List) {
      for (final value in values) {
        final url = _imageUrl(value);
        if (url != null && !urls.contains(url)) urls.add(url);
      }
    }
    return urls;
  }

  /*
    Aquí convierto el texto que llega desde el backend al enum que usa Flutter.
    Esto define si el marcador será de mascota perdida, avistamiento o mascota
    encontrada.
  */
  static ReportType _parseReportType(dynamic value) {
    switch (value?.toString()) {
      case 'lost':
        return ReportType.lost;
      case 'found':
        return ReportType.found;
      case 'sighting':
        return ReportType.sighting;
      default:
        throw const FormatException('Tipo de reporte no soportado');
    }
  }

  /*
    Aquí convierto coordenadas que pueden llegar como número o como texto.
    Si llega un valor inválido uso 0.0 para evitar que la app se rompa.
  */
  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /*
    Aquí doy un formato sencillo a la fecha recibida desde PostgreSQL.
    No agrego paquetes adicionales para no tocar dependencias del proyecto.
  */
  static String _formatDateText(dynamic value) {
    return formatReportDateTimeInBogota(value);
  }
}

double distanceBetweenMeters(LatLng from, LatLng to) {
  const earthRadiusMeters = 6371000.0;
  double radians(double degrees) => degrees * math.pi / 180.0;
  final dLat = radians(to.latitude - from.latitude);
  final dLng = radians(to.longitude - from.longitude);
  final lat1 = radians(from.latitude);
  final lat2 = radians(to.latitude);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

MapReport? selectNearestReport(List<MapReport> reports, LatLng? userLocation) {
  if (reports.isEmpty) return null;
  final ordered = List<MapReport>.of(reports);
  ordered.sort((a, b) {
    if (userLocation != null) {
      final byDistance = distanceBetweenMeters(
        userLocation,
        a.position,
      ).compareTo(distanceBetweenMeters(userLocation, b.position));
      if (byDistance != 0) return byDistance;
    }
    final aDate = a.occurredAt;
    final bDate = b.occurredAt;
    if (aDate != null && bDate != null) {
      final byNewestDate = bDate.compareTo(aDate);
      if (byNewestDate != 0) return byNewestDate;
    } else if (aDate != null) {
      return -1;
    } else if (bDate != null) {
      return 1;
    }
    return a.id.compareTo(b.id);
  });
  return ordered.first;
}

/* ============================================================================
   PÁGINA PRINCIPAL DEL MAPA
   ============================================================================ */

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;
  LatLng? _userLocation;
  LatLng? _pendingCameraTarget;

  MapFilter _selectedFilter = MapFilter.active;
  MapStatus _status = MapStatus.loaded;
  MapReport? _selectedReport;

  /*
    Aquí guardo los íconos personalizados del mapa.
    Estos íconos se crean por código con Canvas para no depender
    de imágenes externas por cada marcador.

    Mientras los íconos terminan de cargarse, el mapa usa los
    marcadores normales de Google Maps como respaldo.
  */
  BitmapDescriptor? _lostMarkerIcon;
  BitmapDescriptor? _sightingMarkerIcon;
  BitmapDescriptor? _foundMarkerIcon;

  static const Color backgroundColor = Color(0xFFDDEFE2);

  /*
    Aquí dejé el mapa centrado en Ciudad Salitre Occidental, Bogotá, porque
    esa es la zona definida como alcance inicial del proyecto.
  */
  static const LatLng _ciudadSalitre = LatLng(4.6569, -74.1095);

  /*
    Aquí defino la URL del backend que entrega los reportes del mapa.

    Para Android Emulator se usa 10.0.2.2 porque localhost dentro del emulador
    apunta al propio emulador, no al computador donde corre el backend.

    Si luego probamos en un celular físico, esta URL debe cambiarse por la IP
    local del computador, por ejemplo: http://192.168.x.x:3000/api/map/reports.
  */
  static const String _mapReportsUrl = 'http://10.0.2.2:3000/api/map/reports';

  /* --------------------------------------------------------------------------
     DATOS DEL MAPA CONSULTADOS DESDE EL BACKEND
     -------------------------------------------------------------------------- */

  /*
    Estas listas se llenan con la información real que llega desde PostgreSQL
    por medio del backend.
  */
  List<MapReport> _activeReports = [];
  List<MapReport> _foundReports = [];

  /* --------------------------------------------------------------------------
     DATOS VISIBLES SEGÚN FILTRO
     -------------------------------------------------------------------------- */

  /*
    Aquí controlo qué reportes se muestran según el filtro seleccionado.
    Si el estado del mapa no está cargado, no muestro marcadores.
  */
  List<MapReport> get _visibleReports {
    if (_status != MapStatus.loaded) return [];

    if (_selectedFilter == MapFilter.active) {
      return _activeReports;
    }

    return _foundReports;
  }

  /*
    Aquí convierto los reportes visibles en marcadores de Google Maps.
    Ahora uso marcadores personalizados con forma de pin y una huellita blanca
    en el centro.

    Para no romper la carga inicial del mapa, dejo un marcador normal de Google
    como respaldo mientras se generan los íconos personalizados.
  */
  Set<Marker> get _markers {
    return _visibleReports.map((report) {
      BitmapDescriptor markerIcon;

      if (report.type == ReportType.lost) {
        markerIcon =
            _lostMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      } else if (report.type == ReportType.found) {
        markerIcon =
            _foundMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      } else {
        markerIcon =
            _sightingMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      }

      return Marker(
        markerId: MarkerId(report.id),
        position: report.position,
        icon: markerIcon,

        /*
          Aquí dejé desactivado el texto nativo del marcador para que la
          interacción principal sea la tarjeta inferior personalizada.
        */
        infoWindow: InfoWindow.noText,
        onTap: () {
          setState(() {
            _selectedReport = report;
          });
        },
      );
    }).toSet();
  }

  /* --------------------------------------------------------------------------
     MARCADORES PERSONALIZADOS DEL MAPA
     -------------------------------------------------------------------------- */

  /*
    Aquí cargo los marcadores personalizados que se van a usar en el GoogleMap.
    El marcador rojo se usa para mascotas perdidas y el marcador verde
    se usa para avistamientos y mascotas encontradas.
  */
  Future<void> _loadCustomMarkers() async {
    _lostMarkerIcon = await _createPawMarker(
      pinColor: markerColorForReportType(ReportType.lost),
    );

    _sightingMarkerIcon = await _createPawMarker(
      pinColor: markerColorForReportType(ReportType.sighting),
    );

    _foundMarkerIcon = await _createPawMarker(
      pinColor: markerColorForReportType(ReportType.found),
    );

    /*
      Aquí actualizo la pantalla cuando los íconos ya están listos.
      Esto hace que los marcadores normales sean reemplazados por los pines
      personalizados sin afectar la carga inicial del mapa.
    */
    if (mounted) {
      setState(() {});
    }
  }

  /*
    Aquí dibujo el marcador personalizado directamente con Canvas.
    Esto permite tener un pin con huellita blanca sin agregar archivos PNG
    adicionales al proyecto.
  */
  Future<BitmapDescriptor> _createPawMarker({required Color pinColor}) async {
    const int width = 120;
    const int height = 150;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint pinPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill;

    final Paint pawPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    /*
      Aquí dibujo una sombra inferior para que el pin se vea con más profundidad
      sobre el mapa.
    */
    canvas.drawOval(const Rect.fromLTWH(38, 128, 44, 12), shadowPaint);

    /*
      Aquí dibujo la forma principal del pin. La punta queda hacia abajo para
      que señale la ubicación exacta del reporte o avistamiento.
    */
    final Path pinPath = Path()
      ..moveTo(width / 2, height - 12)
      ..cubicTo(30, 95, 18, 75, 18, 52)
      ..cubicTo(18, 22, 42, 8, width / 2, 8)
      ..cubicTo(78, 8, 102, 22, 102, 52)
      ..cubicTo(102, 75, 90, 95, width / 2, height - 12)
      ..close();

    canvas.drawPath(pinPath, shadowPaint);
    canvas.drawPath(pinPath, pinPaint);

    /*
      Aquí agrego un brillo suave dentro del pin para que no se vea plano.
    */
    final Paint innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(width / 2, 52), 36, innerPaint);

    /*
      Aquí dibujo la huellita blanca del centro del marcador.
      Ajustamos la separación entre los dedos para que la huella se entienda mejor
      visualmente y no se vea tan compacta sobre el pin.
    */
    canvas.drawOval(const Rect.fromLTWH(44, 57, 32, 26), pawPaint);

    /*
      Aquí separé un poco más las cuatro patitas de la huella.
      También reduje levemente su tamaño para que cada dedo se diferencie mejor.
    */
    canvas.drawCircle(const Offset(34, 47), 7, pawPaint);
    canvas.drawCircle(const Offset(48, 34), 7, pawPaint);
    canvas.drawCircle(const Offset(72, 34), 7, pawPaint);
    canvas.drawCircle(const Offset(86, 47), 7, pawPaint);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(width, height);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    final Uint8List bytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(bytes);
  }

  /* --------------------------------------------------------------------------
     CONSULTA DE REPORTES DEL MAPA DESDE EL BACKEND
     -------------------------------------------------------------------------- */

  /*
    Aquí consulto el backend para traer los reportes reales del mapa.
    La información viene desde PostgreSQL por medio de la ruta /api/map/reports.

    Esta función reemplaza los datos quemados que antes estaban en _activeReports
    y _foundReports.
  */
  Future<void> _loadMapReports() async {
    try {
      try {
        final location =
            await (widget.locationLoader ??
                DeviceLocationService.getCurrentLocation)();
        _userLocation = LatLng(location.latitude, location.longitude);
      } catch (_) {
        _userLocation = null;
      }
      final Uri url = Uri.parse(_mapReportsUrl);
      final response = await (widget.reportsClient ?? MapReportsClient())
          .getReports(url);

      if (response.statusCode != 200) {
        if (!mounted) return;

        setState(() {
          _status = MapStatus.error;
          _selectedReport = null;
        });

        return;
      }

      final Map<String, dynamic> decodedBody =
          jsonDecode(response.body) as Map<String, dynamic>;

      final List<dynamic> data = decodedBody['data'] as List<dynamic>? ?? [];

      final List<MapReport> reports = [];
      for (final item in data) {
        try {
          final report = MapReport.fromJson(item as Map<String, dynamic>);
          if (report.position.latitude != 0.0 &&
              report.position.longitude != 0.0) {
            reports.add(report);
          }
        } on FormatException {
          // Los tipos desconocidos se omiten; nunca se convierten en avistamiento.
        }
      }

      final List<MapReport> activeReports = reports
          .where(
            (report) =>
                report.type == ReportType.lost ||
                report.type == ReportType.sighting,
          )
          .toList();

      final List<MapReport> foundReports = reports
          .where((report) => report.type == ReportType.found)
          .toList();

      final List<MapReport> visibleReports = _selectedFilter == MapFilter.active
          ? activeReports
          : foundReports;

      if (!mounted) return;

      final selected = selectNearestReport(visibleReports, _userLocation);
      setState(() {
        _activeReports = activeReports;
        _foundReports = foundReports;
        _status = visibleReports.isEmpty ? MapStatus.empty : MapStatus.loaded;
        _selectedReport = selected;
      });

      if (selected != null) {
        await _moveCamera(selected.position);
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = MapStatus.error;
        _selectedReport = null;
      });
    }
  }

  /* --------------------------------------------------------------------------
     ACCIONES DEL MAPA
     -------------------------------------------------------------------------- */

  /*
    Aquí cambio entre reportes activos y reportes encontrados.
    También selecciono el primer reporte disponible para mostrar una tarjeta
    inferior de ejemplo.
  */
  void _toggleFilter(MapFilter filter) {
    final List<MapReport> nextReports = filter == MapFilter.active
        ? _activeReports
        : _foundReports;

    final selected = selectNearestReport(nextReports, _userLocation);
    setState(() {
      _selectedFilter = filter;
      _status = nextReports.isEmpty ? MapStatus.empty : MapStatus.loaded;
      _selectedReport = selected;
    });

    if (selected != null) {
      _moveCamera(selected.position);
    }
  }

  /*
    Aquí reintento cargar el mapa cuando ocurra un error.
    Ahoram el sistema vuelve a consultar el backend para traer información actualizada.
  */
  void _retryLoad() {
    _loadMapReports();
  }

  /*
    Aquí muevo la cámara del mapa hacia un punto específico.
    Lo uso cuando cambio de filtro o cuando quiero volver al centro principal.
  */
  Future<void> _moveCamera(LatLng target) async {
    final controller = _mapController;

    if (controller == null) {
      _pendingCameraTarget = target;
      return;
    }
    _pendingCameraTarget = null;

    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 15.5),
        ),
      );
    } catch (error) {
      if (mounted) debugPrint('No se pudo mover la cámara del mapa: $error');
    }
  }

  void _handleMapCreated(GoogleMapController controller) {
    if (!mounted) {
      controller.dispose();
      return;
    }
    final previous = _mapController;
    if (previous != null && !identical(previous, controller)) {
      previous.dispose();
    }
    _mapController = controller;
    final target = _pendingCameraTarget;
    if (target != null) _moveCamera(target);
  }

  /*
    Aquí conecté el botón + con el zoom real del GoogleMap.
    Antes el control era visual, pero no modificaba la cámara del mapa.
  */
  Future<void> _zoomIn() async {
    final controller = _mapController;

    if (controller == null) return;

    await controller.animateCamera(CameraUpdate.zoomIn());
  }

  /*
    Aquí conecté el botón - con el zoom real del GoogleMap.
    Esto permite alejar el mapa sin mostrar los controles nativos de Google.
  */
  Future<void> _zoomOut() async {
    final controller = _mapController;

    if (controller == null) return;

    await controller.animateCamera(CameraUpdate.zoomOut());
  }

  /*
    Aquí hice funcional el botón de ubicación.
    Por ahora no uso la ubicación real del usuario, sino que regreso el mapa
    al centro definido para Ciudad Salitre Occidental.

    Importante: no cambio el estado del mapa a empty, porque eso ocultaría
    los reportes que ya fueron cargados desde la base de datos.
  */
  Future<void> _goToProjectZone() async {
    await _moveCamera(_userLocation ?? _ciudadSalitre);

    setState(() {
      _selectedReport = null;
    });
  }

  /* --------------------------------------------------------------------------
     CICLO DE VIDA
     -------------------------------------------------------------------------- */

  @override
  void initState() {
    super.initState();

    /*
      Aquí inicio la creación de los marcadores con huellita.
      Se cargan al iniciar la pantalla para que el GoogleMap pueda usarlos
      en reportes perdidos, avistamientos y encontrados.
    */
    _loadCustomMarkers();

    /*
      Aquí consulto el backend apenas entra la pantalla.
      Así el mapa se carga con datos reales de PostgreSQL en lugar de datos
      quemados dentro del archivo.
    */
    _loadMapReports();
  }

  @override
  void dispose() {
    final controller = _mapController;
    _mapController = null;
    controller?.dispose();
    super.dispose();
  }

  /* --------------------------------------------------------------------------
     UI PRINCIPAL
     -------------------------------------------------------------------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,

      /*
        Aquí mantengo el nuevo menú lateral reutilizable que se agregó en el
        proyecto. Así el mapa queda integrado con la navegación general sin
        volver al menú hamburguesa local que teníamos antes.
      */
      drawer: const AniMapSideMenu(),

      body: Column(
        children: [
          /*
            Aquí uso el encabezado reutilizable, el cuál es el logo del proyecto.
          */
          const TopMenuAnimap(),

          MapReportFilterBar(
            selectedFilter: _selectedFilter,
            onActiveTap: () => _toggleFilter(MapFilter.active),
            onFoundTap: () => _toggleFilter(MapFilter.found),
          ),

          Expanded(
            child: Stack(
              children: [
                _GoogleMapArea(
                  status: _status,
                  markers: _markers,
                  initialPosition: _ciudadSalitre,
                  onMapCreated: _handleMapCreated,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onMyLocationTap: _goToProjectZone,
                  onMapTap: () {
                    setState(() {
                      _selectedReport = null;
                    });
                  },
                ),

                Positioned(
                  top: 16,
                  left: 14,
                  child: _Legend(selectedFilter: _selectedFilter),
                ),

                if (_status == MapStatus.empty) const _EmptyStateCard(),

                if (_status == MapStatus.error)
                  _ErrorStateCard(onRetry: _retryLoad),

                if (_status == MapStatus.loaded && _selectedReport != null)
                  Positioned(
                    left: 16,
                    right: 16,

                    bottom: 38,

                    child: MapReportPreviewCard(
                      report: _selectedReport!,
                      onClose: () {
                        setState(() {
                          _selectedReport = null;
                        });
                      },
                    ),
                  ),

                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _LocationBar(),
                ),
              ],
            ),
          ),
        ],
      ),

      /*
        Aquí mantengo la barra inferior nueva del proyecto para no romper los
        cambios de navegación que agregaron tus compañeros.
      */
      bottomNavigationBar: const BottomMenuAnimap(currentIndex: 0),
    );
  }
}

/* ============================================================================
   COMPONENTE DEL GOOGLE MAP REAL
   ============================================================================ */

class _GoogleMapArea extends StatelessWidget {
  final MapStatus status;
  final Set<Marker> markers;
  final LatLng initialPosition;
  final ValueChanged<GoogleMapController> onMapCreated;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onMyLocationTap;
  final VoidCallback onMapTap;

  const _GoogleMapArea({
    required this.status,
    required this.markers,
    required this.initialPosition,
    required this.onMapCreated,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onMyLocationTap,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled =
        status == MapStatus.empty || status == MapStatus.error;

    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: disabled ? 0.45 : 1,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialPosition,
                zoom: 15,
              ),
              markers: markers,
              onTap: (_) => onMapTap(),
              onMapCreated: onMapCreated,
              myLocationButtonEnabled: false,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
            ),
          ),
        ),
        Positioned(
          top: 80,
          left: 14,
          child: _ZoomControl(onZoomIn: onZoomIn, onZoomOut: onZoomOut),
        ),
        Positioned(
          right: 18,
          bottom: 80,
          child: GestureDetector(
            onTap: onMyLocationTap,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              radius: 20,
              child: Icon(Icons.my_location, color: Colors.grey.shade700),
            ),
          ),
        ),
      ],
    );
  }
}

/* ============================================================================
   FILTROS DEL MAPA
   ============================================================================ */

class MapReportFilterBar extends StatelessWidget {
  final MapFilter selectedFilter;
  final VoidCallback onActiveTap;
  final VoidCallback onFoundTap;

  const MapReportFilterBar({
    super.key,
    required this.selectedFilter,
    required this.onActiveTap,
    required this.onFoundTap,
  });

  @override
  Widget build(BuildContext context) {
    final showingFound = selectedFilter == MapFilter.found;

    return Container(
      key: const ValueKey('map-report-filter-bar'),
      height: showingFound ? 84 : 68,
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FilterButton(
                  text: 'Activos',
                  selected: selectedFilter == MapFilter.active,
                  onTap: onActiveTap,
                ),
                const SizedBox(width: 8),
                _FilterButton(
                  text: 'Encontrados',
                  selected: showingFound,
                  onTap: onFoundTap,
                ),
              ],
            ),
            if (showingFound) ...[
              const SizedBox(height: 3),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Mascotas encontradas en los últimos 30 días',
                    maxLines: 1,
                    style: TextStyle(
                      color: Color(0xFF668274),
                      fontSize: 11,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _FilterButton({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  static const Color primaryGreen = Color(0xFF4E967B);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: 34,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? primaryGreen : const Color(0xFFE5F4EC),
          foregroundColor: selected ? Colors.white : const Color(0xFF405466),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: BorderSide(
              color: selected ? primaryGreen : const Color(0xFFBFDCCB),
            ),
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/* ============================================================================
   LEYENDA - CARTÉL DEL MAPA arriba a la izquierda(mascota perdida, avistamiento)
   ============================================================================ */

class _Legend extends StatelessWidget {
  final MapFilter selectedFilter;

  const _Legend({required this.selectedFilter});

  @override
  Widget build(BuildContext context) {
    final bool found = selectedFilter == MapFilter.found;

    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 5),
        ],
      ),
      child: found
          ? const Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Color(0xFF3F9568)),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Mascota encontrada',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            )
          : const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: Color(0xFFE96F67)),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Mascota perdida',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 5),
                Row(
                  children: [
                    Icon(Icons.visibility, size: 16, color: Color(0xFFF2A65A)),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Avistamiento',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/* ============================================================================
   CONTROL DE ZOOM PERSONALIZADO
   ============================================================================ */

class _ZoomControl extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _ZoomControl({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 4),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onZoomIn,
            child: const SizedBox(
              height: 36,
              child: Center(child: Text('+', style: TextStyle(fontSize: 25))),
            ),
          ),
          const Divider(height: 1),
          GestureDetector(
            onTap: onZoomOut,
            child: const SizedBox(
              height: 36,
              child: Center(child: Text('−', style: TextStyle(fontSize: 25))),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================================
   TARJETA INFERIOR DEL REPORTE SELECCIONADO
   ============================================================================ */

class _MapPetPhoto extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final Color color;

  const _MapPetPhoto({
    required this.imageUrl,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) return _fallback();
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFDDEFE2),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.pets, color: color, size: size * 0.55),
    );
  }
}

class MapReportPreviewCard extends StatelessWidget {
  final MapReport report;
  final VoidCallback onClose;

  const MapReportPreviewCard({
    super.key,
    required this.report,
    required this.onClose,
  });

  static const Color primaryGreen = Color(0xFF4E967B);
  static const Color darkText = Color(0xFF405466);

  @override
  Widget build(BuildContext context) {
    final bool isLost = report.type == ReportType.lost;
    final bool isSighting = report.type == ReportType.sighting;

    final String dateLabel = isLost
        ? 'Última vez visto'
        : isSighting
        ? 'Reportado el'
        : 'Fecha de cierre';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MapPetPhoto(
                imageUrl: report.imageUrl,
                size: 56,
                color: isLost ? const Color(0xFFE96F67) : primaryGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.title,
                        style: const TextStyle(
                          color: darkText,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${report.petName} · ${report.details}',
                        style: const TextStyle(
                          color: Color(0xFF65756C),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '$dateLabel: ${report.dateText}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      Text(
                        'Ubicación: ${report.location}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Descripción: ${report.description}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, height: 1.25),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    report.type == ReportType.sighting
                                    ? SightingDetailPage(report: report)
                                    : ReportDetailPage(report: report),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Ver Detalle',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: onClose,
              child: const Icon(
                Icons.close,
                size: 19,
                color: Color(0xFF789085),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================================
   ESTADO VACÍO
   ============================================================================ */

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 295,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pets, size: 42, color: Color(0xFF8EB5A5)),
            SizedBox(height: 14),
            Text(
              'No hay reportes disponibles',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF405466),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Actualmente no hay reportes de mascotas perdidas o avistadas en este mapa.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF77877E), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================================
   ESTADO DE ERROR
   ============================================================================ */

class _ErrorStateCard extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorStateCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 285,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_rounded,
              size: 58,
              color: Color(0xFFE96F67),
            ),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar el mapa',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF405466),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ocurrió un problema temporal al cargar la información. Verifica tu conexión e inténtalo nuevamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF77877E),
                fontSize: 11,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 30,
              width: 180,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4E967B),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================================
   BARRA DE UBICACIÓN INFERIOR
   ============================================================================ */

class _LocationBar extends StatelessWidget {
  const _LocationBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: Colors.white.withOpacity(0.9),
      child: const Row(
        children: [
          Icon(Icons.home, size: 16, color: Color(0xFF4E967B)),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Ciudad Salitre Occidental, Bogotá',
              style: TextStyle(color: Color(0xFF52675C), fontSize: 12),
            ),
          ),
          Icon(Icons.keyboard_arrow_up, size: 16, color: Color(0xFF52675C)),
        ],
      ),
    );
  }
}

typedef ReportMapBuilder =
    Widget Function(BuildContext context, LatLng position, bool interactive);

class SightingDetailPage extends StatelessWidget {
  const SightingDetailPage({super.key, required this.report, this.mapBuilder});

  final MapReport report;
  final ReportMapBuilder? mapBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F5),
      appBar: AppBar(
        title: const Text('Detalle del avistamiento'),
        backgroundColor: const Color(0xFFFFE8CC),
        foregroundColor: const Color(0xFF344955),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
          children: [
            if (report.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  report.imageUrl!,
                  key: const ValueKey('sighting-detail-photo'),
                  height: 230,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 180,
                    child: ColoredBox(
                      color: Color(0xFFFFE8CC),
                      child: Icon(Icons.visibility_outlined, size: 54),
                    ),
                  ),
                ),
              ),
            if (report.imageUrl != null) const SizedBox(height: 14),
            _ReportSectionCard(
              icon: Icons.visibility_outlined,
              title: 'Avistamiento',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReportInfoLine(
                    icon: Icons.schedule,
                    label: 'Fecha y hora',
                    value: report.dateText,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    report.description,
                    style: const TextStyle(
                      color: Color(0xFF5E6F66),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ReportSectionCard(
              icon: Icons.link,
              title: 'Vinculación',
              child: report.isLinked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.petName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (report.details.isNotEmpty) Text(report.details),
                        const SizedBox(height: 5),
                        const Text(
                          'Vinculado a un reporte activo de mascota perdida.',
                          style: TextStyle(color: Color(0xFF65756C)),
                        ),
                      ],
                    )
                  : const Text(
                      'Avistamiento sin reporte vinculado.',
                      key: ValueKey('independent-sighting-label'),
                      style: TextStyle(color: Color(0xFF65756C)),
                    ),
            ),
            const SizedBox(height: 14),
            _ReportSectionCard(
              icon: Icons.location_on_outlined,
              title: 'Ubicación del avistamiento',
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 185,
                      child: _ReportLocationMap(
                        position: report.position,
                        interactive: false,
                        mapBuilder: mapBuilder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReportLocationViewPage(
                            position: report.position,
                            mapBuilder: mapBuilder,
                            title: 'Ubicación del avistamiento',
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Ver ubicación en mapa'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportDetailPage extends StatelessWidget {
  final MapReport report;
  final ReportMapBuilder? mapBuilder;

  const ReportDetailPage({super.key, required this.report, this.mapBuilder});

  List<String> get _photos {
    final result = <String>[];
    if (report.imageUrl != null) result.add(report.imageUrl!);
    for (final image in report.imageUrls) {
      if (!result.contains(image)) result.add(image);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isFinalized = report.type == ReportType.found;
    final statusColor = isFinalized
        ? const Color(0xFF3F9568)
        : const Color(0xFFE7655D);
    final photos = _photos;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F3),
      appBar: AppBar(
        title: const Text('Detalle del reporte'),
        backgroundColor: const Color(0xFFDFF3E8),
        foregroundColor: const Color(0xFF344955),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
          children: [
            _ReportPetHeader(
              report: report,
              statusLabel: isFinalized ? 'FINALIZADO' : 'ACTIVO',
              statusColor: statusColor,
            ),
            const SizedBox(height: 14),
            _ReportSectionCard(
              icon: Icons.description_outlined,
              title: 'Información del reporte',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReportInfoLine(
                    icon: Icons.calendar_today_outlined,
                    label: 'Fecha del reporte',
                    value: report.createdDateText.isEmpty
                        ? report.dateText
                        : report.createdDateText,
                  ),
                  if (isFinalized)
                    _ReportInfoLine(
                      icon: Icons.event_available_outlined,
                      label: 'Fecha de cierre',
                      value: report.closedDateText.isEmpty
                          ? report.dateText
                          : report.closedDateText,
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Descripción',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    report.description,
                    style: const TextStyle(
                      color: Color(0xFF5E6F66),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ReportSectionCard(
              icon: Icons.location_on_outlined,
              title: 'Última ubicación reportada',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 175,
                      child: _ReportLocationMap(
                        position: report.position,
                        interactive: false,
                        mapBuilder: mapBuilder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _ReportInfoLine(
                    icon: Icons.pin_drop_outlined,
                    label: 'Ubicación',
                    value: 'Punto marcado en el mapa',
                  ),
                  if (report.reference.trim().isNotEmpty)
                    _ReportInfoLine(
                      icon: Icons.notes_outlined,
                      label: 'Referencia adicional',
                      value: report.reference.trim(),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('open-report-location'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReportLocationViewPage(
                            position: report.position,
                            mapBuilder: mapBuilder,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Ver ubicación en mapa'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ReportSectionCard(
              icon: Icons.photo_library_outlined,
              title: 'Fotos de la mascota',
              child: photos.isEmpty
                  ? const Text(
                      'Esta mascota no tiene fotos disponibles.',
                      style: TextStyle(color: Color(0xFF65756C)),
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 92,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length.clamp(0, 5),
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 9),
                            itemBuilder: (context, index) =>
                                _ReportPhotoThumbnail(
                                  key: ValueKey('report-preview-photo-$index'),
                                  url: photos[index],
                                  isPrincipal: index == 0,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReportPhotoViewerPage(
                                        photos: photos,
                                        initialIndex: index,
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey('open-report-gallery'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReportPhotoGalleryPage(photos: photos),
                              ),
                            ),
                            icon: const Icon(Icons.grid_view_rounded),
                            label: Text(
                              'Ver todas las fotos (${photos.length})',
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (report.isOwner) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F4EB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFB9DCC5)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: Color(0xFF357552),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Este reporte es tuyo',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!isFinalized) ...[
              const SizedBox(height: 14),
              _ReportSectionCard(
                icon: Icons.contact_phone_outlined,
                title: 'Contacto del dueño',
                child: report.showContact
                    ? _OwnerContactCard(report: report)
                    : const Text(
                        'El dueño no ha habilitado contacto directo para este reporte.',
                        style: TextStyle(
                          color: Color(0xFF65756C),
                          height: 1.35,
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportPetHeader extends StatelessWidget {
  const _ReportPetHeader({
    required this.report,
    required this.statusLabel,
    required this.statusColor,
  });

  final MapReport report;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 112,
              height: 112,
              child: report.imageUrl == null
                  ? const ColoredBox(
                      color: Color(0xFFE5F1E8),
                      child: Icon(
                        Icons.pets,
                        size: 48,
                        color: Color(0xFF478061),
                      ),
                    )
                  : Image.network(
                      report.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFFE5F1E8),
                        child: Icon(Icons.pets, size: 48),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.petName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF344955),
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  report.details,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF65756C), height: 1.3),
                ),
                const SizedBox(height: 10),
                _StatusChip(text: statusLabel, color: statusColor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportSectionCard extends StatelessWidget {
  const _ReportSectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1EAE4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF3F9568)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF344955),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ReportInfoLine extends StatelessWidget {
  const _ReportInfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF5C8870)),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: Color(0xFF5E6F66), height: 1.35),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportLocationMap extends StatelessWidget {
  const _ReportLocationMap({
    required this.position,
    required this.interactive,
    this.mapBuilder,
  });

  final LatLng position;
  final bool interactive;
  final ReportMapBuilder? mapBuilder;

  @override
  Widget build(BuildContext context) {
    if (mapBuilder != null) return mapBuilder!(context, position, interactive);
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: position, zoom: 16),
      markers: {
        Marker(markerId: const MarkerId('report-location'), position: position),
      },
      liteModeEnabled: !interactive,
      compassEnabled: interactive,
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      scrollGesturesEnabled: interactive,
      zoomGesturesEnabled: interactive,
      rotateGesturesEnabled: interactive,
      tiltGesturesEnabled: interactive,
      zoomControlsEnabled: interactive,
    );
  }
}

class ReportLocationViewPage extends StatelessWidget {
  const ReportLocationViewPage({
    super.key,
    required this.position,
    this.mapBuilder,
    this.title = 'Última ubicación reportada',
  });

  final LatLng position;
  final ReportMapBuilder? mapBuilder;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF3F9568),
        foregroundColor: Colors.white,
      ),
      body: _ReportLocationMap(
        position: position,
        interactive: true,
        mapBuilder: mapBuilder,
      ),
    );
  }
}

class _ReportPhotoThumbnail extends StatelessWidget {
  const _ReportPhotoThumbnail({
    super.key,
    required this.url,
    required this.isPrincipal,
    required this.onTap,
    this.fillCell = false,
    this.headers,
  });

  final String url;
  final bool isPrincipal;
  final VoidCallback onTap;
  final bool fillCell;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isPrincipal ? 'Foto principal' : 'Foto de mascota',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: fillCell ? double.infinity : 92,
          height: fillCell ? double.infinity : 92,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.network(
                  url,
                  headers: headers,
                  cacheWidth: fillCell ? 360 : 240,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFE6ECE8),
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              if (isPrincipal)
                const Positioned(
                  left: 5,
                  bottom: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xDD2E7651),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Text(
                        'Principal',
                        style: TextStyle(color: Colors.white, fontSize: 9),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportPhotoGalleryPage extends StatelessWidget {
  const ReportPhotoGalleryPage({super.key, required this.photos, this.headers});

  final List<String> photos;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Todas las fotos (${photos.length})'),
        backgroundColor: const Color(0xFFDFF3E8),
      ),
      body: GridView.builder(
        key: const ValueKey('read-only-report-gallery'),
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 7,
          mainAxisSpacing: 7,
        ),
        itemCount: photos.length,
        itemBuilder: (context, index) => _ReportPhotoThumbnail(
          key: ValueKey('report-gallery-photo-$index'),
          url: photos[index],
          isPrincipal: index == 0,
          fillCell: true,
          headers: headers,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportPhotoViewerPage(
                photos: photos,
                initialIndex: index,
                headers: headers,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReportPhotoViewerPage extends StatefulWidget {
  const ReportPhotoViewerPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.headers,
  });

  final List<String> photos;
  final int initialIndex;
  final Map<String, String>? headers;

  @override
  State<ReportPhotoViewerPage> createState() => _ReportPhotoViewerPageState();
}

class _ReportPhotoViewerPageState extends State<ReportPhotoViewerPage> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} de ${widget.photos.length}'),
      ),
      body: PageView.builder(
        key: const ValueKey('report-photo-viewer'),
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (_, index) => InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Center(
            child: Image.network(
              widget.photos[index],
              headers: widget.headers,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OwnerContactCard extends StatelessWidget {
  final MapReport report;

  const _OwnerContactCard({required this.report});

  /*
    Aquí abro la aplicación de teléfono del dispositivo con el número del dueño.
    No realiza la llamada automáticamente; solo dejo el número listo para que
    el usuario decida si quiere llamar.
  */
  Future<void> _openPhoneDialer(BuildContext context) async {
    final String cleanPhone = report.ownerPhone.replaceAll(' ', '');

    final Uri phoneUri = Uri(scheme: 'tel', path: cleanPhone);

    final bool opened = await launchUrl(
      phoneUri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible abrir la aplicación de teléfono.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC7E1D1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(label: 'Teléfono', value: report.ownerPhone),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: () => _openPhoneDialer(context),
              icon: const Icon(Icons.phone, size: 18),
              label: const Text('Contactar dueño'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4E967B),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Color(0xFF405466),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF65756C)),
            ),
          ),
        ],
      ),
    );
  }
}
