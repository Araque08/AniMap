import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../auth/data/session_manager.dart';
import '../../../map/presentation/pages/map_page.dart';
import '../../../notifications/data/notification_target_service.dart';
import '../../data/photo_matches_service.dart';
import '../../data/report_datetime.dart';
import '../../data/reports_service.dart';
import 'own_report_detail_page.dart';

typedef PhotoMatchesLoader = Future<List<PhotoMatch>> Function(int? before);

abstract class _PrivateMatchState<T extends StatefulWidget> extends State<T> {
  SessionManager get session;
  int? _epoch;
  void clearPrivateData();
  @override
  void initState() {
    super.initState();
    _epoch = session.authenticatedSessionGeneration;
    session.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (_epoch == session.authenticatedSessionGeneration) return;
    _epoch = session.authenticatedSessionGeneration;
    if (mounted) setState(clearPrivateData);
  }

  bool current(int? generation) =>
      mounted &&
      session.isAuthenticated &&
      generation == session.authenticatedSessionGeneration;
  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

class PhotoMatchesPage extends StatefulWidget {
  const PhotoMatchesPage({super.key, this.loader, this.sessionManager});
  final PhotoMatchesLoader? loader;
  final SessionManager? sessionManager;
  @override
  State<PhotoMatchesPage> createState() => _PhotoMatchesPageState();
}

class _PhotoMatchesPageState extends _PrivateMatchState<PhotoMatchesPage> {
  @override
  SessionManager get session =>
      widget.sessionManager ?? SessionManager.instance;
  final _service = PhotoMatchesService();
  List<PhotoMatch> _items = [];
  bool _loading = false, _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void clearPrivateData() {
    _items = [];
    _loading = false;
    _more = true;
    _error = 'La sesión cambió. Consulta nuevamente con tu cuenta.';
  }

  Future<void> _load({bool next = false}) async {
    if (_loading || !session.isAuthenticated) return;
    final generation = session.authenticatedSessionGeneration;
    final before = next && _items.isNotEmpty ? _items.last.id : null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items =
          await (widget.loader?.call(before) ?? _service.list(before: before));
      if (!current(generation)) return;
      setState(() {
        _items = next
            ? [
                ..._items,
                ...items.where(
                  (item) => !_items.any((old) => old.id == item.id),
                ),
              ]
            : items;
        _more = items.isNotEmpty;
      });
    } catch (error) {
      if (current(generation)) {
        setState(
          () => _error = error is PhotoMatchesException
              ? error.message
              : 'No se pudo cargar el historial.',
        );
      }
    } finally {
      if (current(generation)) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Coincidencias fotográficas')),
    body: !session.isAuthenticated
        ? const Center(
            child: Text('Inicia sesión para consultar tus coincidencias.'),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Posibles coincidencias. La similitud visual no confirma que sea la misma mascota.',
              ),
              if (_error != null) ...[
                Text(_error!),
                TextButton(
                  onPressed: _loading ? null : () => _load(),
                  child: const Text('Reintentar'),
                ),
              ],
              if (!_loading && _error == null && _items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Aún no tienes coincidencias fotográficas.'),
                ),
              for (final item in _items)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.image_search),
                    title: Text(item.petName),
                    subtitle: Text('Similitud visual: ${item.percentage}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PhotoMatchDetailPage(
                          matchId: item.id,
                          sessionManager: session,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (!_loading && _more && _items.isNotEmpty)
                TextButton(
                  onPressed: () => _load(next: true),
                  child: const Text('Cargar más'),
                ),
            ],
          ),
  );
}

class PhotoMatchDetailPage extends StatefulWidget {
  const PhotoMatchDetailPage({
    super.key,
    required this.matchId,
    this.sessionManager,
    this.loader,
    this.imageLoader,
    this.reportLoader,
    this.mapBuilder,
  });
  final int matchId;
  final SessionManager? sessionManager;
  final Future<PhotoMatch> Function(int)? loader;
  final Future<Uint8List> Function(int)? imageLoader;
  final Future<OwnReportDetails> Function(int)? reportLoader;
  final ReportMapBuilder? mapBuilder;
  @override
  State<PhotoMatchDetailPage> createState() => _PhotoMatchDetailPageState();
}

class _PhotoMatchDetailPageState
    extends _PrivateMatchState<PhotoMatchDetailPage> {
  @override
  SessionManager get session =>
      widget.sessionManager ?? SessionManager.instance;
  final _service = PhotoMatchesService();
  PhotoMatch? _item;
  Uint8List? _image;
  bool _loading = false;
  bool _openingSighting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void clearPrivateData() {
    _item = null;
    _image = null;
    _loading = false;
    _openingSighting = false;
    _error = 'La sesión cambió. Consulta nuevamente con tu cuenta.';
  }

  Future<void> _load() async {
    if (_loading || !session.isAuthenticated) return;
    final generation = session.authenticatedSessionGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _item = null;
      _image = null;
    });
    try {
      final item = await (widget.loader ?? _service.detail)(widget.matchId);
      if (!current(generation)) return;
      setState(() => _item = item);
      try {
        final image = await (widget.imageLoader ?? _service.image)(
          widget.matchId,
        );
        if (current(generation)) setState(() => _image = image);
      } catch (_) {
        /* The authorized detail remains useful without its photo. */
      }
    } catch (error) {
      if (current(generation)) {
        setState(
          () => _error = error is PhotoMatchesException
              ? error.message
              : 'No se pudo cargar la coincidencia.',
        );
      }
    } finally {
      if (current(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _openSighting() async {
    if (_openingSighting || !session.isAuthenticated) return;
    final generation = session.authenticatedSessionGeneration;
    setState(() => _openingSighting = true);
    try {
      // Reauthorize the private match before following its existing public sighting.
      final item = await (widget.loader ?? _service.detail)(widget.matchId);
      if (!current(generation)) return;
      final sightingId = int.tryParse(item.data['sightingId'].toString());
      final data = sightingId == null || sightingId <= 0
          ? null
          : await NotificationTargetService.buscarAvistamiento(sightingId);
      if (!mounted || !current(generation)) return;
      if (data == null) {
        throw const PhotoMatchesException(
          'El avistamiento ya no está disponible.',
        );
      }
      final report = MapReport.fromJson(data);
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ListenableBuilder(
            listenable: session,
            builder: (_, _) => current(generation)
                ? SightingDetailPage(report: report)
                : const Scaffold(
                    body: Center(
                      child: Text(
                        'La sesión cambió. Abre el avistamiento con tu cuenta.',
                      ),
                    ),
                  ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted || !current(generation)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is PhotoMatchesException
                ? error.message
                : 'No se pudo abrir el avistamiento. Intenta nuevamente.',
          ),
        ),
      );
    } finally {
      if (current(generation)) setState(() => _openingSighting = false);
    }
  }

  String _date(dynamic value) => reportDateTimeInBogota(value) == null
      ? 'Fecha no disponible'
      : formatReportDateTimeInBogota(value);

  Widget _locationMap(Map? location) {
    final lat = double.tryParse(location?['lat']?.toString() ?? '');
    final lng = double.tryParse(location?['lng']?.toString() ?? '');
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return const Text('Ubicación no disponible.');
    }
    final position = LatLng(lat, lng);
    return Semantics(
      key: const ValueKey('match-location-map'),
      label: 'Mapa de la ubicación del avistamiento',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 220,
          child:
              widget.mapBuilder?.call(context, position, false) ??
              GoogleMap(
                key: ValueKey('match-${widget.matchId}-$lat-$lng'),
                initialCameraPosition: CameraPosition(
                  target: position,
                  zoom: 16,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('match-sighting-location'),
                    position: position,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueOrange,
                    ),
                  ),
                },
                liteModeEnabled: true,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                zoomControlsEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                onTap: (_) {},
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final location = item?.data['location'] as Map?;
    final reporter = item?.data['reporter'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('Posible coincidencia')),
      body: !session.isAuthenticated
          ? const Center(
              child: Text('Inicia sesión para ver esta coincidencia.'),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('Reintentar'),
                  ),
                ],
                if (item != null) ...[
                  Text(
                    item.petName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('Similitud visual: ${item.percentage}'),
                  Text(
                    'Descripción del avistamiento: ${item.data['description'] ?? 'No disponible'}',
                  ),
                  const Text(
                    'La similitud visual no confirma que sea la misma mascota.',
                  ),
                  const SizedBox(height: 16),
                  if (_image != null)
                    Image.memory(
                      _image!,
                      height: 240,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('Fotografía no disponible.'),
                    )
                  else if (!_loading)
                    const Text('Fotografía no disponible.'),
                  const SizedBox(height: 16),
                  Text(
                    'Fecha del avistamiento: ${_date(item.data['observedAt'])}',
                  ),
                  Text('Fecha del evento: ${_date(item.data['createdAt'])}'),
                  Text(
                    'Hora de Colombia',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  const Text('Ubicación del avistamiento'),
                  if (location?['address'] case final String address
                      when address.trim().isNotEmpty)
                    Text(address),
                  const SizedBox(height: 8),
                  _locationMap(location),
                  const SizedBox(height: 12),
                  Text(
                    'Reportante: ${reporter?['label'] ?? 'Persona de la comunidad'}',
                  ),
                  if (reporter?['phone'] case final String phone
                      when phone.isNotEmpty)
                    Text('Teléfono compartido: $phone')
                  else
                    const Text('El reportante no compartió su teléfono.'),
                  if (int.tryParse(item.data['sightingId'].toString())
                      case final int sightingId when sightingId > 0)
                    OutlinedButton.icon(
                      key: const ValueKey('match-open-sighting'),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(
                        _openingSighting
                            ? 'Consultando...'
                            : 'Ver avistamiento',
                      ),
                      onPressed: _openingSighting ? null : _openSighting,
                    ),
                  if (int.tryParse(item.data['reportId'].toString())
                      case final int reportId when reportId > 0)
                    OutlinedButton.icon(
                      key: const ValueKey('match-open-report'),
                      icon: const Icon(Icons.pets),
                      label: const Text('Ver mi reporte'),
                      onPressed: () {
                        final generation =
                            session.authenticatedSessionGeneration;
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ListenableBuilder(
                              listenable: session,
                              builder: (_, _) => current(generation)
                                  ? OwnReportDetailPage(
                                      reportId: reportId,
                                      loader: widget.reportLoader,
                                    )
                                  : const Scaffold(
                                      body: Center(
                                        child: Text(
                                          'La sesión cambió. Abre el reporte con tu cuenta.',
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  Text(
                    'Estado del aviso: ${item.data['notificationState'] ?? 'Registrado'}',
                  ),
                ],
              ],
            ),
    );
  }
}
