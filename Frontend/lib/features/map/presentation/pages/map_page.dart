import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../../auth/data/auth_service.dart';
import '../../../report/data/report_datetime.dart';

class MapPage extends StatefulWidget {
  final String userName;

  const MapPage({super.key, this.userName = ''});

  @override
  State<MapPage> createState() => _MapPageState();
}

/* ============================================================================
   ENUMS DEL MAPA
   ============================================================================ */

enum MapFilter { active, found }

enum MapStatus { loaded, empty, error }

enum ReportType { lost, sighting, found }

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
  final String description;
  final String dateText;
  final String? imageUrl;
  final LatLng position;
  final ReportType type;

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
    required this.description,
    required this.dateText,
    required this.imageUrl,
    required this.position,
    required this.type,
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
    return MapReport(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Reporte',
      petName: json['petName']?.toString() ?? 'No identificado',
      details: json['details']?.toString() ?? '',
      location: json['location']?.toString() ?? 'Ubicación no disponible',
      description: json['description']?.toString() ?? 'Sin descripción',
      dateText: _formatDateText(json['dateText']),
      imageUrl: _imageUrl(json['imageUrl']),
      position: LatLng(_toDouble(json['lat']), _toDouble(json['lng'])),
      type: _parseReportType(json['type']),
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
        return ReportType.sighting;
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

/* ============================================================================
   PÁGINA PRINCIPAL DEL MAPA
   ============================================================================ */

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;

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
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
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
    _lostMarkerIcon = await _createPawMarker(pinColor: const Color(0xFFE96F67));

    _sightingMarkerIcon = await _createPawMarker(
      pinColor: const Color(0xFF4E967B),
    );

    _foundMarkerIcon = await _createPawMarker(
      pinColor: const Color(0xFF4E967B),
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
      final Uri url = Uri.parse(_mapReportsUrl);
      final token = AuthService.accessToken;
      final http.Response response = await http.get(
        url,
        headers: token == null || token.isEmpty
            ? const {}
            : {'Authorization': 'Bearer $token'},
      );

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

      final List<MapReport> reports = data
          .map((item) => MapReport.fromJson(item as Map<String, dynamic>))
          .where(
            /*
              Aquí evito pintar marcadores sin coordenadas válidas.
              Esto protege el mapa si llega algún registro incompleto desde
              la base de datos.
            */
            (report) =>
                report.position.latitude != 0.0 &&
                report.position.longitude != 0.0,
          )
          .toList();

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

      setState(() {
        _activeReports = activeReports;
        _foundReports = foundReports;
        _status = visibleReports.isEmpty ? MapStatus.empty : MapStatus.loaded;
        _selectedReport = visibleReports.isNotEmpty
            ? visibleReports.first
            : null;
      });

      if (visibleReports.isNotEmpty) {
        await _moveCamera(visibleReports.first.position);
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

    setState(() {
      _selectedFilter = filter;
      _status = nextReports.isEmpty ? MapStatus.empty : MapStatus.loaded;
      _selectedReport = nextReports.isNotEmpty ? nextReports.first : null;
    });

    if (nextReports.isNotEmpty) {
      _moveCamera(nextReports.first.position);
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

    if (controller == null) return;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 15.5),
      ),
    );
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
    await _moveCamera(_ciudadSalitre);

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
    _mapController?.dispose();
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

          _FilterBar(
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
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
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

                    child: _ReportPreviewCard(
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

class _FilterBar extends StatelessWidget {
  final MapFilter selectedFilter;
  final VoidCallback onActiveTap;
  final VoidCallback onFoundTap;

  const _FilterBar({
    required this.selectedFilter,
    required this.onActiveTap,
    required this.onFoundTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      color: Colors.white,
      child: Center(
        child: Row(
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
              selected: selectedFilter == MapFilter.found,
              onTap: onFoundTap,
            ),
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
                Icon(Icons.location_on, size: 16, color: Color(0xFF4E967B)),
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
                    Icon(Icons.location_on, size: 16, color: Color(0xFF4E967B)),
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

class _ReportPreviewCard extends StatelessWidget {
  final MapReport report;
  final VoidCallback onClose;

  const _ReportPreviewCard({required this.report, required this.onClose});

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
                                    _ReportDetailPage(report: report),
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

/* ============================================================================
   PANTALLA TEMPORAL DE DETALLE DEL REPORTE
   ============================================================================ */

/*
  Aquí dejé una pantalla temporal para el detalle del reporte.
  La idea es que el botón "Ver Detalle" ya tenga una navegación real.

  En la versión final esta pantalla debería conectarse con el backend para traer
  la información completa del reporte, la mascota, sus fotos, ubicación y datos
  permitidos del dueño.
*/
class _ReportDetailPage extends StatelessWidget {
  final MapReport report;

  const _ReportDetailPage({required this.report});

  @override
  Widget build(BuildContext context) {
    final bool isLost = report.type == ReportType.lost;
    final bool isSighting = report.type == ReportType.sighting;
    final bool isFound = report.type == ReportType.found;

    final String dateLabel = isLost
        ? 'Última vez visto'
        : isSighting
        ? 'Reportado el'
        : 'Fecha de cierre';

    final String statusLabel = isFound
        ? 'Finalizado'
        : isSighting
        ? 'Avistamiento'
        : 'Activo';

    final Color statusColor = isLost
        ? const Color(0xFFE96F67)
        : const Color(0xFF4E967B);

    return Scaffold(
      backgroundColor: const Color(0xFFDDEFE2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFDDF2E7),
        elevation: 0,
        foregroundColor: const Color(0xFF405466),
        title: Text(report.title),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  /*
                    Aquí hago que la tarjeta ocupe prácticamente toda la pantalla
                    disponible, para que el detalle no quede flotando arriba con
                    mucho espacio vacío en la parte inferior.
                  */
                  minHeight: constraints.maxHeight - 34,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: _MapPetPhoto(
                          imageUrl: report.imageUrl,
                          size: 84,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        report.petName,
                        style: const TextStyle(
                          color: Color(0xFF405466),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        report.details,
                        style: const TextStyle(
                          color: Color(0xFF65756C),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _StatusChip(text: statusLabel, color: statusColor),
                      const SizedBox(height: 22),

                      /*
                        Aquí muestro la información principal del reporte.
                        La etiqueta de fecha cambia según el tipo de caso:
                        perdido, avistamiento o encontrado.
                      */
                      _DetailRow(label: 'Tipo', value: report.title),
                      _DetailRow(label: dateLabel, value: report.dateText),
                      _DetailRow(label: 'Ubicación', value: report.location),
                      const SizedBox(height: 20),
                      const Text(
                        'Descripción',
                        style: TextStyle(
                          color: Color(0xFF405466),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        report.description,
                        style: const TextStyle(
                          color: Color(0xFF65756C),
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),

                      /*
                        Aquí agrego espacio flexible para que, cuando el detalle
                        tenga poca información, el contenido no se vea comprimido
                        arriba y la tarjeta conserve presencia en toda la pantalla.
                      */
                      if (report.type != ReportType.lost)
                        const SizedBox(height: 32),

                      if (report.type == ReportType.lost && report.isOwner) ...[
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF6EF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFC7E1D1)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified_user_outlined),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Este reporte es tuyo',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (report.type == ReportType.lost) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Contacto del dueño',
                          style: TextStyle(
                            color: Color(0xFF405466),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (report.showContact)
                          _OwnerContactCard(report: report)
                        else
                          const Text(
                            'El dueño no ha habilitado contacto directo para este reporte.',
                            style: TextStyle(
                              color: Color(0xFF65756C),
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
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
