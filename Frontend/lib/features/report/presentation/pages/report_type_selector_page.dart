
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:animap/widgets/bottom_menu_animap.dart';
import 'package:animap/features/report/data/mascotas_perdidas_service.dart';

class ReportarBuscarPage extends StatefulWidget {
  const ReportarBuscarPage({
    super.key,
    this.onReportarPerdida,
    this.onReportarAvistamiento,
    this.onInicio,
    this.onPerfil,
    this.onAccionCentral,
    this.onImagenSeleccionada,
  });

  final VoidCallback? onReportarPerdida;
  final VoidCallback? onReportarAvistamiento;
  final VoidCallback? onInicio;
  final VoidCallback? onPerfil;
  final VoidCallback? onAccionCentral;
  final ValueChanged<XFile>? onImagenSeleccionada;

  @override
  State<ReportarBuscarPage> createState() =>
      _ReportarBuscarPageState();
}

class _ReportarBuscarPageState
    extends State<ReportarBuscarPage> {
  static const Color verde = Color(0xFF21986A);
  static const Color fondo = Color(0xFFF4FAF6);
  static const Color verdeClaro = Color(0xFFE7F8EE);
  static const Color gris = Color(0xFF778397);

  final TextEditingController _busqueda =
  TextEditingController();

  final ImagePicker _picker = ImagePicker();

  final MascotasPerdidasService _servicio =
  MascotasPerdidasService();

  List<MascotaReporte> _reportes = [];

  bool _cargando = true;
  bool _mostrarAvistamientos = false;
  String _filtro = 'Todos';
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _servicio.dispose();
    super.dispose();
  }

  // =====================================================
  // CONSULTAR REPORTES REALES DESDE EL BACKEND
  // =====================================================

  Future<void> _cargarReportes() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final datos = await _servicio.obtenerReportes();

      if (!mounted) return;

      setState(() {
        _reportes = datos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  // =====================================================
  // BUSQUEDA Y FILTROS
  // =====================================================

  List<MascotaReporte> get _resultados {
    final texto = _busqueda.text.trim().toLowerCase();

    return _reportes.where((mascota) {
      if (_mostrarAvistamientos) {
        if (!mascota.esAvistamiento) return false;
      } else {
        if (!mascota.estaPerdida) return false;
      }

      final detalles = mascota.detalles.toLowerCase();

      if (_filtro == 'Perros' &&
          !detalles.contains('perro')) {
        return false;
      }

      if (_filtro == 'Gatos' &&
          !detalles.contains('gato')) {
        return false;
      }

      final contenido = [
        mascota.nombre,
        mascota.detalles,
        mascota.ubicacion,
        mascota.referencia,
        mascota.descripcion,
      ].join(' ').toLowerCase();

      return contenido.contains(texto);
    }).toList();
  }

  void _abrirFiltros() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filtrar por especie',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...['Todos', 'Perros', 'Gatos'].map(
                    (tipo) => ListTile(
                  title: Text(tipo),
                  trailing: _filtro == tipo
                      ? const Icon(
                    Icons.check_circle,
                    color: verde,
                  )
                      : null,
                  onTap: () {
                    setState(() => _filtro = tipo);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // CAMARA Y GALERIA
  // =====================================================

  Future<void> _seleccionarImagen(
      ImageSource origen,
      ) async {
    try {
      final imagen = await _picker.pickImage(
        source: origen,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (!mounted || imagen == null) return;

      widget.onImagenSeleccionada?.call(imagen);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Imagen seleccionada. '
                'La comparación automática está pendiente '
                'de conectar al backend.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo seleccionar la imagen: $e',
          ),
        ),
      );
    }
  }

  void _abrirCamara() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Buscar mascota por imagen',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Toma una foto o selecciona una imagen '
                    'para buscar posibles coincidencias.',
                textAlign: TextAlign.center,
                style: TextStyle(color: gris),
              ),
              const SizedBox(height: 15),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: verde,
                ),
                title: const Text('Tomar fotografía'),
                onTap: () {
                  Navigator.pop(context);
                  _seleccionarImagen(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: verde,
                ),
                title: const Text('Seleccionar de galería'),
                onTap: () {
                  Navigator.pop(context);
                  _seleccionarImagen(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // FORMATO DE FECHAS
  // =====================================================

  String _formatearFecha(DateTime? fecha) {
    if (fecha == null) return 'Fecha no disponible';

    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];

    final local = fecha.toLocal();

    return '${local.day} '
        '${meses[local.month - 1]} '
        '${local.year}';
  }

  String _ubicacionVisible(MascotaReporte mascota) {
    if (mascota.ubicacion.isNotEmpty &&
        mascota.ubicacion != 'Punto marcado en el mapa') {
      return mascota.ubicacion;
    }

    if (mascota.referencia.trim().isNotEmpty) {
      return mascota.referencia;
    }

    return 'Ubicación en el mapa';
  }

  // =====================================================
  // BOTONES DE REPORTES
  // =====================================================

  Widget _botonAccion({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required VoidCallback? accion,
  }) {
    return Expanded(
      child: Material(
        color: verdeClaro,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: accion ??
                  () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Falta conectar la pantalla: $titulo',
                    ),
                  ),
                );
              },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icono, color: verde, size: 30),
                const SizedBox(height: 9),
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  descripcion,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: gris,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // FOTOGRAFIA DE MASCOTA
  // =====================================================

  Widget _fotoMascota(
      String? imagen, {
        BoxFit ajuste = BoxFit.cover,
      }) {
    if (imagen == null || imagen.isEmpty) {
      return const ColoredBox(
        color: verdeClaro,
        child: Center(
          child: Icon(
            Icons.pets,
            color: verde,
            size: 45,
          ),
        ),
      );
    }

    return Image.network(
      imagen,
      fit: ajuste,
      width: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return const ColoredBox(
          color: verdeClaro,
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: verde,
              size: 40,
            ),
          ),
        );
      },
      loadingBuilder: (context, child, progreso) {
        if (progreso == null) return child;

        return const Center(
          child: CircularProgressIndicator(
            color: verde,
            strokeWidth: 2,
          ),
        );
      },
    );
  }


  Future<void> _reportarAvistamientoDeMascota(
      MascotaReporte mascota,
      ) async {
    if (!mascota.estaPerdida) return;

    // El backend identifica los reportes como lost_18,
    // lost_19, etc. Extraemos el ID real del reporte.
    final reporteId = int.tryParse(
      mascota.id.replaceFirst('lost_', ''),
    );

    if (reporteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo identificar el reporte de esta mascota.',
          ),
        ),
      );
      return;
    }

    await Navigator.pushNamed(
      context,
      '/create-sighting',
      arguments: reporteId,
    );

    if (!mounted) return;

    // Actualizamos el catálogo al regresar.
    await _cargarReportes();
  }


  // =====================================================
  // DETALLE DEL REPORTE REAL
  // =====================================================

  void _abrirDetalle(MascotaReporte mascota) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 230,
                  child: _fotoMascota(mascota.imagenUrl),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                mascota.nombre,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                mascota.detalles,
                style: const TextStyle(color: gris),
              ),
              const Divider(height: 28),
              const Text(
                'Información del reporte',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _datoDetalle(
                Icons.location_on_outlined,
                'Ubicación',
                _ubicacionVisible(mascota),
              ),
              _datoDetalle(
                Icons.calendar_month_outlined,
                'Fecha',
                _formatearFecha(mascota.fecha),
              ),
              _datoDetalle(
                Icons.info_outline,
                'Descripción',
                mascota.descripcion.isNotEmpty
                    ? mascota.descripcion
                    : 'Sin descripción registrada',
              ),
              const SizedBox(height: 16),
              if (mascota.imagenes.length > 1) ...[
                const Text(
                  'Más fotografías',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 95,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: mascota.imagenes.length,
                    separatorBuilder: (_, __) =>
                    const SizedBox(width: 9),
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius:
                        BorderRadius.circular(12),
                        child: SizedBox(
                          width: 95,
                          child: _fotoMascota(
                            mascota.imagenes[index],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 20),

              if (mascota.estaPerdida && !mascota.esPropietario) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);

                      _reportarAvistamientoDeMascota(mascota);
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text(
                      'Reportar avistamiento de esta mascota',
                      textAlign: TextAlign.center,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: verde,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 17,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _datoDetalle(
      IconData icono,
      String titulo,
      String valor,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: verde, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(valor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // TARJETA DE MASCOTA
  // =====================================================

  Widget _tarjetaMascota(MascotaReporte mascota) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirDetalle(mascota),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fotografía real desde el backend.
            SizedBox(
              height: 145,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _fotoMascota(mascota.imagenUrl),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: mascota.esAvistamiento
                            ? Colors.blue
                            : const Color(0xFFF04455),
                        borderRadius:
                        BorderRadius.circular(7),
                      ),
                      child: Text(
                        mascota.esAvistamiento
                            ? 'VISTA'
                            : 'PERDIDA',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.favorite_border,
                      color: Colors.white,
                      size: 25,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Datos reales de PostgreSQL.
            Padding(
              padding:
              const EdgeInsets.fromLTRB(9, 8, 9, 7),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    mascota.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    mascota.detalles,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: gris,
                      fontSize: 10.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: verde,
                        size: 15,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          _ubicacionVisible(mascota),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: gris,
                            fontSize: 10.5,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month,
                        color: verde,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _formatearFecha(mascota.fecha),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: gris,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // PESTAÑAS
  // =====================================================

  Widget _pestana(String titulo, bool avistamientos) {
    final seleccionada =
        _mostrarAvistamientos == avistamientos;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _mostrarAvistamientos = avistamientos;
          });
        },
        child: Column(
          children: [
            Padding(
              padding:
              const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: seleccionada ? verde : gris,
                ),
              ),
            ),
            Container(
              height: 3,
              color: seleccionada
                  ? verde
                  : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // LISTADO CON CARGA Y ERRORES
  // =====================================================

  Widget _contenidoCatalogo() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(45),
        child: Center(
          child: CircularProgressIndicator(color: verde),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.wifi_off_outlined,
              color: Colors.redAccent,
              size: 35,
            ),
            const SizedBox(height: 10),
            const Text(
              'No se pudieron cargar los reportes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: gris,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargarReportes,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final resultados = _resultados;

    if (resultados.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const Icon(
              Icons.pets_outlined,
              color: verde,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              _mostrarAvistamientos
                  ? 'No hay avistamientos para mostrar.'
                  : 'No hay mascotas perdidas para mostrar.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: gris),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding:
      const EdgeInsets.symmetric(horizontal: 9),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: resultados.length,
        gridDelegate:
        const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
          mainAxisExtent: 285,
        ),
        itemBuilder: (context, index) {
          return _tarjetaMascota(resultados[index]);
        },
      ),
    );
  }

  // =====================================================
  // PANTALLA PRINCIPAL
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondo,
      bottomNavigationBar: const BottomMenuAnimap(
        currentIndex: 1,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    color: verde,
                    onRefresh: _cargarReportes,
                    child: ListView(
                      physics:
                      const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        14, 18, 14, 24,
                      ),
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Reportar y Buscar',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight:
                                      FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Reporta, busca o ayuda a '
                                        'reunir mascotas con sus familias.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: gris,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.map_outlined,
                                color: verde,
                                size: 28,
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Conecta aquí el mapa '
                                          'existente de AniMap.',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Acciones principales
                        SizedBox(
                          height: 145,
                          child: Row(
                            children: [

                              _botonAccion(
                                icono: Icons.campaign_outlined,
                                titulo: 'Reportar mascota perdida',
                                descripcion:
                                'Publica la información de tu mascota.',
                                accion: () async {
                                  if (widget.onReportarPerdida != null) {
                                    widget.onReportarPerdida!();
                                    return;
                                  }

                                  await Navigator.pushNamed(
                                    context,
                                    '/create-lost-report',
                                  );

                                  if (mounted) {
                                    await _cargarReportes();
                                  }
                                },
                              ),

                              const SizedBox(width: 10),

                              _botonAccion(
                                icono: Icons.visibility_outlined,
                                titulo: 'Registrar avistamiento',
                                descripcion:
                                'Informa sobre una mascota que viste.',
                                accion: () async {
                                  if (widget.onReportarAvistamiento != null) {
                                    widget.onReportarAvistamiento!();
                                    return;
                                  }

                                  await Navigator.pushNamed(
                                    context,
                                    '/create-sighting',
                                  );

                                  if (mounted) {
                                    await _cargarReportes();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Catálogo
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                            BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  _pestana(
                                    'Mascotas perdidas',
                                    false,
                                  ),
                                  _pestana(
                                    'Avistamientos',
                                    true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Buscador
                              Padding(
                                padding:
                                const EdgeInsets.symmetric(
                                  horizontal: 9,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _busqueda,
                                        onChanged: (_) {
                                          setState(() {});
                                        },
                                        decoration:
                                        InputDecoration(
                                          hintText:
                                          'Nombre, raza o zona...',
                                          hintStyle:
                                          const TextStyle(
                                            fontSize: 11,
                                            color: gris,
                                          ),
                                          prefixIcon:
                                          const Icon(
                                            Icons.search,
                                            color: gris,
                                          ),
                                          filled: true,
                                          fillColor:
                                          const Color(
                                            0xFFF5F7F7,
                                          ),
                                          border:
                                          OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius
                                                .circular(13),
                                            borderSide:
                                            BorderSide.none,
                                          ),
                                          contentPadding:
                                          const EdgeInsets
                                              .symmetric(
                                            vertical: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    IconButton(
                                      tooltip: 'Filtros',
                                      onPressed: _abrirFiltros,
                                      icon: const Icon(
                                        Icons.filter_alt_outlined,
                                        color: verde,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 13),

                              _contenidoCatalogo(),

                              const SizedBox(height: 15),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              ],
            ),

            // Cámara flotante lateral
            Positioned(
              right: 12,
              bottom: 20,
              child: FloatingActionButton(
                heroTag: 'camara_busqueda_animap',
                onPressed: _abrirCamara,
                backgroundColor: verde,
                foregroundColor: Colors.white,
                tooltip: 'Buscar mascota por imagen',
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 29,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

