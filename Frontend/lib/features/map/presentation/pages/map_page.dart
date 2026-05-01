import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../faq/presentation/screens/faq_screen.dart';

class MapPage extends StatefulWidget {
  final String userName;

  const MapPage({
    super.key,
    required this.userName,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

/* ============================================================================
   ENUMS DEL MAPA
   ============================================================================ */

enum MapFilter {
  active,
  found,
}

enum MapStatus {
  loaded,
  empty,
  error,
}

enum ReportType {
  lost,
  sighting,
  found,
}

/* ============================================================================
   MODELO TEMPORAL PARA LOS REPORTES DEL MAPA
   ============================================================================ */

/*
  Aquí definí un modelo temporal para representar los reportes y avistamientos
  que se muestran en el mapa. Por ahora estos datos están quemados en el código,
  porque mi parte actual es dejar funcional la interfaz del mapa sin depender
  todavía del backend.

  Más adelante, estos datos deben venir desde la base de datos y los endpoints
  correspondientes de reportes, avistamientos y ubicaciones.
*/
class MapReport {
  final String id;
  final String title;
  final String petName;
  final String details;
  final String location;
  final String description;
  final String dateText;
  final String imageAsset;
  final LatLng position;
  final ReportType type;

  /*
    Aquí agregué los datos de contacto del dueño. Esto aplica principalmente
    para reportes de pérdida.

    La idea es respetar la lógica del campo mostrar_contacto: si el dueño
    autorizó mostrar sus datos, el detalle permite ver nombre y teléfono.
    No muestro el correo en la interfaz porque para este flujo es más útil
    contactar directamente por llamada.
  */
  final bool showContact;
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
    required this.imageAsset,
    required this.position,
    required this.type,
    required this.showContact,
    required this.ownerName,
    required this.ownerPhone,
    required this.ownerEmail,
  });
}

/* ============================================================================
   PÁGINA PRINCIPAL DEL MAPA
   ============================================================================ */

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;

  MapFilter _selectedFilter = MapFilter.active;
  MapStatus _status = MapStatus.loaded;
  bool _menuOpen = false;
  MapReport? _selectedReport;

  static const Color backgroundColor = Color(0xFFDDEFE2);

  /*
    Aquí dejé el mapa centrado en Ciudad Salitre Occidental, Bogotá, porque
    esa es la zona definida como alcance inicial del proyecto.
  */
  static const LatLng _ciudadSalitre = LatLng(4.6569, -74.1095);

  /* --------------------------------------------------------------------------
     DATOS QUEMADOS TEMPORALES
     -------------------------------------------------------------------------- */

  /*
    Aquí quemé algunos reportes activos para simular mascotas perdidas y
    avistamientos dentro de Ciudad Salitre Occidental.

    Estos datos me permiten probar el comportamiento del mapa, los marcadores,
    el panel inferior y la pantalla de detalle sin depender todavía del backend.
  */
  final List<MapReport> _activeReports = const [
    MapReport(
      id: 'lost_1',
      title: 'Mascota perdida',
      petName: 'Max',
      details: 'Perro · Golden Retriever · Dorado',
      location: 'Carrera 53, Ciudad Salitre Occidental',
      description:
      'Visto por última vez corriendo hacia la avenida. Parece asustado y responde al nombre de Max.',
      dateText: '12 Abr 2024, 10:30 AM',
      imageAsset: 'assets/images/logo_animap.png',
      position: LatLng(4.6577, -74.1082),
      type: ReportType.lost,
      showContact: true,
      ownerName: 'Felipe Quevedo',
      ownerPhone: '300 123 4567',
      ownerEmail: 'FelipeQuevedo@gmail.com',
    ),
    MapReport(
      id: 'lost_2',
      title: 'Mascota perdida',
      petName: 'Luna',
      details: 'Gato · Criollo · Gris',
      location: 'Calle 24C, Ciudad Salitre Occidental',
      description:
      'Se perdió cerca al conjunto residencial. Tiene collar azul y suele esconderse en zonas verdes.',
      dateText: '12 Abr 2024, 2:15 PM',
      imageAsset: 'assets/images/logo_animap.png',
      position: LatLng(4.6559, -74.1112),
      type: ReportType.lost,
      showContact: true,
      ownerName: 'Laura Gómez',
      ownerPhone: '311 456 7890',
      ownerEmail: 'laura.gomez@email.com',
    ),
    MapReport(
      id: 'sighting_1',
      title: 'Avistamiento',
      petName: 'No identificado',
      details: 'Especie: Perro · Color claro',
      location: 'Parque Ciudad Salitre',
      description:
      'Fue visto caminando solo cerca de la zona verde. No tenía collar visible.',
      dateText: '12 Abr 2024, 3:40 PM',
      imageAsset: 'assets/images/logo_animap.png',
      position: LatLng(4.6586, -74.1101),
      type: ReportType.sighting,
      showContact: false,
      ownerName: 'Usuario de la comunidad',
      ownerPhone: '',
      ownerEmail: '',
    ),
    MapReport(
      id: 'sighting_2',
      title: 'Avistamiento',
      petName: 'No identificado',
      details: 'Especie: Gato · Color oscuro',
      location: 'Carrera 60, Ciudad Salitre Occidental',
      description:
      'Visto cerca a la Carrera 60. Parece estar perdido y se mantiene cerca de los edificios.',
      dateText: '13 Abr 2024, 8:20 AM',
      imageAsset: 'assets/images/logo_animap.png',
      position: LatLng(4.6549, -74.1078),
      type: ReportType.sighting,
      showContact: false,
      ownerName: 'Usuario de la comunidad',
      ownerPhone: '',
      ownerEmail: '',
    ),
  ];

  /*
    Aquí quemé reportes encontrados para probar el filtro "Encontrados".
    En la versión final, estos datos deberían venir del backend filtrados
    por estado del reporte.
  */
  final List<MapReport> _foundReports = const [
    MapReport(
      id: 'found_1',
      title: 'Mascota encontrada',
      petName: 'Pluto',
      details: 'Perro · Golden Retriever · Macho',
      location: 'Pablo Andrade, Ciudad Salitre Occidental',
      description:
      'El reporte fue finalizado porque el dueño confirmó que la mascota fue encontrada.',
      dateText: '14 Abr 2024, 11:00 AM',
      imageAsset: 'assets/images/logo_animap.png',
      position: LatLng(4.6565, -74.1068),
      type: ReportType.found,
      showContact: false,
      ownerName: 'Equipo AniMap',
      ownerPhone: '',
      ownerEmail: '',
    ),
    MapReport(
      id: 'found_2',
      title: 'Mascota encontrada',
      petName: 'Milo',
      details: 'Gato · Criollo · Gris',
      location: 'Av. La Esperanza, Ciudad Salitre Occidental',
      description: 'El dueño cerró el caso porque la mascota regresó a casa.',
      dateText: '15 Abr 2024, 6:45 PM',
      imageAsset: 'assets/images/logo_animap.png',
      position: LatLng(4.6591, -74.1124),
      type: ReportType.found,
      showContact: false,
      ownerName: 'Equipo AniMap',
      ownerPhone: '',
      ownerEmail: '',
    ),
  ];

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
    Uso rojo para mascotas perdidas y verde para avistamientos o encontradas.
  */
  Set<Marker> get _markers {
    return _visibleReports.map((report) {
      final BitmapDescriptor markerColor = report.type == ReportType.lost
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);

      return Marker(
        markerId: MarkerId(report.id),
        position: report.position,
        icon: markerColor,

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
     ACCIONES DEL MAPA
     -------------------------------------------------------------------------- */

  /*
    Aquí cambio entre reportes activos y reportes encontrados.
    También selecciono el primer reporte disponible para mostrar una tarjeta
    inferior de ejemplo.
  */
  void _toggleFilter(MapFilter filter) {
    final List<MapReport> nextReports =
    filter == MapFilter.active ? _activeReports : _foundReports;

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
    Por ahora vuelve a cargar los datos quemados disponibles.
  */
  void _retryLoad() {
    final List<MapReport> reports =
    _selectedFilter == MapFilter.active ? _activeReports : _foundReports;

    setState(() {
      _status = reports.isEmpty ? MapStatus.empty : MapStatus.loaded;
      _selectedReport = reports.isNotEmpty ? reports.first : null;
    });

    _moveCamera(_ciudadSalitre);
  }

  /*
    Aquí abro o cierro el menú lateral.
  */
  void _toggleMenu() {
    setState(() {
      _menuOpen = !_menuOpen;
    });
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
        CameraPosition(
          target: target,
          zoom: 15.5,
        ),
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

    await controller.animateCamera(
      CameraUpdate.zoomIn(),
    );
  }

  /*
    Aquí conecté el botón - con el zoom real del GoogleMap.
    Esto permite alejar el mapa sin mostrar los controles nativos de Google.
  */
  Future<void> _zoomOut() async {
    final controller = _mapController;

    if (controller == null) return;

    await controller.animateCamera(
      CameraUpdate.zoomOut(),
    );
  }

  /*
    Aquí hice funcional el botón de ubicación.
    Por ahora no uso la ubicación real del usuario, sino que regreso el mapa
    al centro definido para Ciudad Salitre Occidental.
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
      Aquí dejo seleccionado el primer reporte activo para que al entrar
      al mapa se vea una tarjeta inicial.
    */
    if (_activeReports.isNotEmpty) {
      _selectedReport = _activeReports.first;
    }
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
      body: Stack(
        children: [
          Column(
            children: [
              _Header(
                onMenuTap: _toggleMenu,
              ),
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
                      child: _Legend(
                        selectedFilter: _selectedFilter,
                      ),
                    ),
                    if (_status == MapStatus.empty) const _EmptyStateCard(),
                    if (_status == MapStatus.error)
                      _ErrorStateCard(
                        onRetry: _retryLoad,
                      ),
                    if (_status == MapStatus.loaded && _selectedReport != null)
                      Positioned(
                        left: 16,
                        right: 16,

                        /*
                          Aquí subo un poco la tarjeta del reporte para que el botón "Ver Detalle"
                          no quede montado sobre la barra inferior de ubicación.
                        */
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
              _BottomNavigation(
                onHomeTap: _retryLoad,
                onCreateTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Aquí irá crear reporte.'),
                    ),
                  );
                },
                onProfileTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Perfil de ${widget.userName}'),
                    ),
                  );
                },
              ),
            ],
          ),
          if (_menuOpen)
            _SideMenu(
              onClose: _toggleMenu,
              onLostPets: () {
                setState(() {
                  _menuOpen = false;
                  _selectedFilter = MapFilter.active;
                  _status = MapStatus.loaded;
                  _selectedReport =
                  _activeReports.isNotEmpty ? _activeReports.first : null;
                });
                _moveCamera(_ciudadSalitre);
              },
              onMyPets: () {
                setState(() {
                  _menuOpen = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Aquí irá Mis Mascotas.'),
                  ),
                );
              },
              onFaq: () {
                setState(() {
                  _menuOpen = false;
                });

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FaqScreen(),
                  ),
                );
              },
              onLogout: () {
                Navigator.pop(context);
              },
              onCreateReport: () {
                setState(() {
                  _menuOpen = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Aquí irá Crear reporte.'),
                  ),
                );
              },
            ),
        ],
      ),
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
    final bool disabled = status == MapStatus.empty || status == MapStatus.error;

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
          child: _ZoomControl(
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
          ),
        ),
        Positioned(
          right: 18,
          bottom: 80,
          child: GestureDetector(
            onTap: onMyLocationTap,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              radius: 20,
              child: Icon(
                Icons.my_location,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ============================================================================
   HEADER SUPERIOR
   ============================================================================ */

class _Header extends StatelessWidget {
  final VoidCallback onMenuTap;

  const _Header({
    required this.onMenuTap,
  });

  static const Color darkText = Color(0xFF405466);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 75,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        color: const Color(0xFFDDF2E7),
        child: Row(
          children: [
            GestureDetector(
              onTap: onMenuTap,
              child: const Icon(
                Icons.menu,
                size: 28,
                color: Colors.black87,
              ),
            ),
            const Spacer(),

            /*
              Aquí cambié el logo anterior por el nuevo archivo logo_animap.png.
              Este es el logo que aparece centrado junto a la palabra AniMap
              en el encabezado principal del mapa.
            */
            Image.asset(
              'assets/images/logo_animap.png',
              height: 42,
              fit: BoxFit.contain,
            ),

            const SizedBox(width: 8),

            const Text(
              'AniMap',
              style: TextStyle(
                color: darkText,
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),

            const Spacer(),

            const Icon(
              Icons.notifications,
              size: 26,
              color: Colors.black87,
            ),
          ],
        ),
      ),
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
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/* ============================================================================
   LEYENDA DEL MAPA (mascota perdida, avistamiento)
   ============================================================================ */

class _Legend extends StatelessWidget {
  final MapFilter selectedFilter;

  const _Legend({
    required this.selectedFilter,
  });

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
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 5,
          ),
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

  const _ZoomControl({
    required this.onZoomIn,
    required this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onZoomIn,
            child: const SizedBox(
              height: 36,
              child: Center(
                child: Text('+', style: TextStyle(fontSize: 25)),
              ),
            ),
          ),
          const Divider(height: 1),
          GestureDetector(
            onTap: onZoomOut,
            child: const SizedBox(
              height: 36,
              child: Center(
                child: Text('−', style: TextStyle(fontSize: 25)),
              ),
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

class _ReportPreviewCard extends StatelessWidget {
  final MapReport report;
  final VoidCallback onClose;

  const _ReportPreviewCard({
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
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFDDEFE2),
                child: Icon(
                  Icons.pets,
                  color: isLost ? const Color(0xFFE96F67) : primaryGreen,
                  size: 30,
                ),
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
                                builder: (context) => _ReportDetailPage(
                                  report: report,
                                ),
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
            Icon(
              Icons.pets,
              size: 42,
              color: Color(0xFF8EB5A5),
            ),
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
              style: TextStyle(
                color: Color(0xFF77877E),
                fontSize: 12,
              ),
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

  const _ErrorStateCard({
    required this.onRetry,
  });

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
                child: const Text(
                  'Reintentar',
                  style: TextStyle(fontSize: 12),
                ),
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
          Icon(
            Icons.home,
            size: 16,
            color: Color(0xFF4E967B),
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Ciudad Salitre Occidental, Bogotá',
              style: TextStyle(
                color: Color(0xFF52675C),
                fontSize: 12,
              ),
            ),
          ),
          Icon(
            Icons.keyboard_arrow_up,
            size: 16,
            color: Color(0xFF52675C),
          ),
        ],
      ),
    );
  }
}

/* ============================================================================
   NAVEGACIÓN INFERIOR
   ============================================================================ */

class _BottomNavigation extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onCreateTap;
  final VoidCallback onProfileTap;

  const _BottomNavigation({
    required this.onHomeTap,
    required this.onCreateTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBF8),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 5,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: onHomeTap,
                icon: const Icon(
                  Icons.home,
                  color: Color(0xFF4E967B),
                  size: 34,
                ),
              ),
              const SizedBox(width: 72),
              IconButton(
                onPressed: onProfileTap,
                icon: const Icon(
                  Icons.person,
                  color: Color(0xFF4E967B),
                  size: 34,
                ),
              ),
            ],
          ),
          Positioned(
            top: -3,
            child: GestureDetector(
              onTap: onCreateTap,
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFE2E6E1),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 61,
                    height: 61,
                    decoration: const BoxDecoration(
                      color: Color(0xFF73C15A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.pets,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================================
   MENÚ LATERAL (Menú hamburguesa)
   ============================================================================ */

class _SideMenu extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onLostPets;
  final VoidCallback onMyPets;
  final VoidCallback onFaq;
  final VoidCallback onLogout;
  final VoidCallback onCreateReport;

  const _SideMenu({
    required this.onClose,
    required this.onLostPets,
    required this.onMyPets,
    required this.onFaq,
    required this.onLogout,
    required this.onCreateReport,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onClose,
          child: Container(
            color: Colors.black.withOpacity(0.25),
          ),
        ),
        Container(
          width: MediaQuery.of(context).size.width * 0.78,
          height: double.infinity,
          color: const Color(0xFFFAFCF7),
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          child: Column(
            children: [
              Row(
                children: [
                  /*
                    Aquí uso el mismo logo nuevo en el menú lateral para mantener
                    coherencia visual con el encabezado principal.
                  */
                  Image.asset(
                    'assets/images/logo_animap.png',
                    height: 50,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'AniMap',
                    style: TextStyle(
                      color: Color(0xFF405466),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 65),
              _MenuItem(
                text: 'Mascotas Perdidas',
                onTap: onLostPets,
              ),
              _MenuItem(
                text: 'Mis Mascotas',
                onTap: onMyPets,
              ),
              _MenuItem(
                text: 'Preguntas Frecuentes',
                onTap: onFaq,
              ),
              _MenuItem(
                text: 'Cerrar sesión',
                onTap: onLogout,
              ),
              _MenuItem(
                text: 'Crear reporte',
                onTap: onCreateReport,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _MenuItem({
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(
          color: Color(0xFFC8D5CC),
          thickness: 1,
        ),
        ListTile(
          onTap: onTap,
          title: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
          ),
        ),
      ],
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

  const _ReportDetailPage({
    required this.report,
  });

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

    final Color statusColor =
    isLost ? const Color(0xFFE96F67) : const Color(0xFF4E967B);

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
                        child: CircleAvatar(
                          radius: 42,
                          backgroundColor: const Color(0xFFDDEFE2),
                          child: Icon(
                            Icons.pets,
                            size: 46,
                            color: statusColor,
                          ),
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
                      _StatusChip(
                        text: statusLabel,
                        color: statusColor,
                      ),
                      const SizedBox(height: 22),

                      /*
                        Aquí muestro la información principal del reporte.
                        La etiqueta de fecha cambia según el tipo de caso:
                        perdido, avistamiento o encontrado.
                      */
                      _DetailRow(
                        label: 'Tipo',
                        value: report.title,
                      ),
                      _DetailRow(
                        label: dateLabel,
                        value: report.dateText,
                      ),
                      _DetailRow(
                        label: 'Ubicación',
                        value: report.location,
                      ),
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

                      if (report.type == ReportType.lost) ...[
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

  const _OwnerContactCard({
    required this.report,
  });

  /*
    Aquí abro la aplicación de teléfono del dispositivo con el número del dueño.
    No realizo la llamada automáticamente; solo dejo el número listo para que
    el usuario decida si quiere llamar.
  */
  Future<void> _openPhoneDialer(BuildContext context) async {
    final String cleanPhone = report.ownerPhone.replaceAll(' ', '');

    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: cleanPhone,
    );

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
        border: Border.all(
          color: const Color(0xFFC7E1D1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(
            label: 'Nombre',
            value: report.ownerName,
          ),
          _DetailRow(
            label: 'Teléfono',
            value: report.ownerPhone,
          ),
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

  const _StatusChip({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
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

  const _DetailRow({
    required this.label,
    required this.value,
  });

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
              style: const TextStyle(
                color: Color(0xFF65756C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}