import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../map/presentation/pages/map_page.dart';
import '../../../report/data/report_datetime.dart';
import '../../../report/data/reports_service.dart';
import '../../data/sightings_service.dart';

typedef SightingsHistoryLoader =
    Future<Map<String, dynamic>> Function(int reportId, String period);

typedef SightingsHistoryMapBuilder =
    Widget Function(
      BuildContext context,
      LatLng lossPosition,
      List<Map<String, dynamic>> sightings,
      ValueChanged<Map<String, dynamic>> onSightingTap,
    );

const double historyLossMarkerHue = BitmapDescriptor.hueRed;
const double historySightingMarkerHue = BitmapDescriptor.hueOrange;

String _locationLabel(Map<String, dynamic> location) {
  final address = location['direccion']?.toString().trim() ?? '';
  if (location['metodo'] == 'DIRECCION' && address.isNotEmpty) return address;
  return '${location['metodo']} · ${location['lat']}, ${location['lng']}';
}

Set<Marker> buildSightingsHistoryMarkers({
  required int reportId,
  required LatLng lossPosition,
  required List<Map<String, dynamic>> sightings,
  ValueChanged<Map<String, dynamic>>? onSightingTap,
}) {
  final markers = <Marker>{
    Marker(
      markerId: MarkerId('loss_$reportId'),
      position: lossPosition,
      icon: BitmapDescriptor.defaultMarkerWithHue(historyLossMarkerHue),
      infoWindow: const InfoWindow(title: 'Punto original de pérdida'),
    ),
  };
  for (final sighting in sightings) {
    final location = Map<String, dynamic>.from(sighting['ubicacion'] as Map);
    markers.add(
      Marker(
        markerId: MarkerId('sighting_${sighting['id']}'),
        position: LatLng(
          (location['lat'] as num).toDouble(),
          (location['lng'] as num).toDouble(),
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(historySightingMarkerHue),
        infoWindow: InfoWindow(
          title: 'Avistamiento',
          snippet: formatReportDateTimeInBogota(sighting['fechaHora']),
        ),
        onTap: onSightingTap == null ? null : () => onSightingTap(sighting),
      ),
    );
  }
  return markers;
}

class ReportSightingsSummary extends StatelessWidget {
  const ReportSightingsSummary({
    super.key,
    required this.reportId,
    required this.count,
    required this.onOpen,
  });

  final int reportId;
  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('report-sightings-summary-$reportId'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Avistamientos',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        if (count == 0)
          const Text(
            'Aún no se han reportado avistamientos.',
            style: TextStyle(color: Color(0xFF64756B)),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: ValueKey('open-sightings-$reportId'),
            onPressed: onOpen,
            icon: const Icon(Icons.visibility_outlined),
            label: Text(
              count == 0 ? 'Ver historial' : 'Ver avistamientos ($count)',
            ),
          ),
        ),
      ],
    );
  }
}

class SightingsHistoryPage extends StatefulWidget {
  const SightingsHistoryPage({
    super.key,
    required this.reportId,
    this.loader,
    this.mapBuilder,
  });

  final int reportId;
  final SightingsHistoryLoader? loader;
  final SightingsHistoryMapBuilder? mapBuilder;

  @override
  State<SightingsHistoryPage> createState() => _SightingsHistoryPageState();
}

class _SightingsHistoryPageState extends State<SightingsHistoryPage> {
  static const _green = Color(0xFF3F9568);
  static const _periods = <String, String>{
    'ALL': 'Todos',
    'TODAY': 'Hoy',
    '7D': 'Últimos 7 días',
    '30D': 'Últimos 30 días',
  };

  String _period = 'ALL';
  bool _showMap = false;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _history;
  Map<String, dynamic>? _selectedSighting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await (widget.loader ?? _defaultLoader)(
        widget.reportId,
        _period,
      );
      if (!mounted) return;
      setState(() {
        _history = history;
        _selectedSighting = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _defaultLoader(int reportId, String period) {
    return SightingsService.getReportHistory(
      reportId: reportId,
      period: period,
    );
  }

  List<Map<String, dynamic>> get _sightings {
    final values = _history?['sightings'] as List<dynamic>? ?? const [];
    return values
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> _selectPeriod(String period) async {
    if (_period == period) return;
    setState(() => _period = period);
    await _load();
  }

  MapReport _asMapReport(Map<String, dynamic> sighting) {
    final report = Map<String, dynamic>.from(_history!['report'] as Map);
    final pet = Map<String, dynamic>.from(report['mascota'] as Map);
    final location = Map<String, dynamic>.from(sighting['ubicacion'] as Map);
    final photo = sighting['foto'] is Map
        ? Map<String, dynamic>.from(sighting['foto'] as Map)
        : null;
    final species = pet['especie']?.toString() ?? '';
    final breed = pet['raza']?.toString() ?? '';
    return MapReport(
      id: 'sighting_${sighting['id']}',
      title: 'Avistamiento',
      petName: pet['nombre']?.toString() ?? 'Mascota',
      details: breed.isEmpty ? species : '$species · $breed',
      location: _locationLabel(location),
      reference: '',
      description: sighting['descripcion']?.toString() ?? '',
      dateText: formatReportDateTimeInBogota(sighting['fechaHora']),
      occurredAt: reportDateTimeInBogota(sighting['fechaHora']),
      imageUrl: SightingsService.absoluteImageUrl(photo?['url']),
      position: LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      ),
      type: ReportType.sighting,
      isLinked: true,
      linkedReportId: widget.reportId,
      showContact: false,
      isOwner: false,
      ownerName: '',
      ownerPhone: '',
      ownerEmail: '',
    );
  }

  void _openDetail(Map<String, dynamic> sighting) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SightingDetailPage(report: _asMapReport(sighting)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F5),
      appBar: AppBar(
        title: const Text('Avistamientos'),
        backgroundColor: const Color(0xFFDFF3E8),
        foregroundColor: const Color(0xFF344955),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView()
          : _content(),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 50, color: Colors.redAccent),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final total = (_history?['total'] as num?)?.toInt() ?? 0;
    final report = Map<String, dynamic>.from(_history!['report'] as Map);
    return Column(
      children: [
        _reportContext(report),
        if (total > 0) ...[_viewSelector(), _periodSelector()],
        Expanded(
          child: total == 0
              ? _emptyHistory()
              : _sightings.isEmpty
              ? _emptyPeriod()
              : _showMap
              ? _mapView(report)
              : _listView(),
        ),
      ],
    );
  }

  Widget _reportContext(Map<String, dynamic> report) {
    final pet = Map<String, dynamic>.from(report['mascota'] as Map);
    final photo = report['fotoPrincipal'] is Map
        ? Map<String, dynamic>.from(report['fotoPrincipal'] as Map)
        : null;
    final photoUrl = ReportsService.imageUrl(photo);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          ClipOval(
            child: photoUrl == null
                ? const SizedBox.square(
                    dimension: 48,
                    child: ColoredBox(
                      color: Color(0xFFDFF3E8),
                      child: Icon(Icons.pets, color: _green),
                    ),
                  )
                : Image.network(
                    photoUrl,
                    headers: ReportsService.imageHeaders,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.square(
                      dimension: 48,
                      child: ColoredBox(
                        color: Color(0xFFDFF3E8),
                        child: Icon(Icons.pets, color: _green),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pet['nombre']?.toString() ?? 'Mascota',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${pet['especie'] ?? ''}'
                  '${pet['raza'] == null ? '' : ' · ${pet['raza']}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Chip(label: Text(report['estado']?.toString() ?? '')),
        ],
      ),
    );
  }

  Widget _viewSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _viewButton(
              label: 'Lista',
              icon: Icons.view_list_outlined,
              selected: !_showMap,
              onTap: () => setState(() => _showMap = false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _viewButton(
              label: 'Mapa',
              icon: Icons.map_outlined,
              selected: _showMap,
              onTap: () => setState(() => _showMap = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFFDFF3E8) : Colors.white,
        foregroundColor: const Color(0xFF344955),
        side: BorderSide(color: selected ? _green : const Color(0xFFC7D5CD)),
      ),
    );
  }

  Widget _periodSelector() {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        key: const ValueKey('history-period-selector'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _periods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final entry = _periods.entries.elementAt(index);
          return ChoiceChip(
            key: ValueKey('period-${entry.key}'),
            label: Text(entry.value),
            selected: _period == entry.key,
            onSelected: (_) => _selectPeriod(entry.key),
          );
        },
      ),
    );
  }

  Widget _emptyHistory() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Aún no se han reportado avistamientos.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, color: Color(0xFF64756B)),
        ),
      ),
    );
  }

  Widget _emptyPeriod() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No hay avistamientos para este período.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: Color(0xFF64756B)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _selectPeriod('ALL'),
              child: const Text('Volver a Todos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listView() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const ValueKey('sightings-history-list'),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        itemCount: _sightings.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (context, index) => _sightingCard(_sightings[index]),
      ),
    );
  }

  Widget _sightingCard(Map<String, dynamic> sighting) {
    final location = Map<String, dynamic>.from(sighting['ubicacion'] as Map);
    final photo = sighting['foto'] is Map
        ? Map<String, dynamic>.from(sighting['foto'] as Map)
        : null;
    final photoUrl = SightingsService.absoluteImageUrl(photo?['url']);
    return Card(
      key: ValueKey('history-sighting-${sighting['id']}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(sighting),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: photoUrl == null
                    ? const SizedBox.square(
                        dimension: 78,
                        child: ColoredBox(
                          color: Color(0xFFFFE8CC),
                          child: Icon(Icons.visibility_outlined),
                        ),
                      )
                    : Image.network(
                        photoUrl,
                        key: ValueKey('history-photo-${sighting['id']}'),
                        width: 78,
                        height: 78,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.square(
                          dimension: 78,
                          child: ColoredBox(
                            color: Color(0xFFFFE8CC),
                            child: Icon(Icons.visibility_outlined),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatReportDateTimeInBogota(sighting['fechaHora']),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sighting['descripcion']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _locationLabel(location),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64756B),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapView(Map<String, dynamic> report) {
    final loss = Map<String, dynamic>.from(report['ubicacionPerdida'] as Map);
    final lossPosition = LatLng(
      (loss['lat'] as num).toDouble(),
      (loss['lng'] as num).toDouble(),
    );
    final map = widget.mapBuilder == null
        ? GoogleMap(
            initialCameraPosition: CameraPosition(
              target: lossPosition,
              zoom: 14.5,
            ),
            markers: buildSightingsHistoryMarkers(
              reportId: widget.reportId,
              lossPosition: lossPosition,
              sightings: _sightings,
              onSightingTap: (item) {
                setState(() => _selectedSighting = item);
              },
            ),
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
          )
        : widget.mapBuilder!(
            context,
            lossPosition,
            _sightings,
            (item) => setState(() => _selectedSighting = item),
          );
    return Stack(
      key: const ValueKey('sightings-history-map'),
      children: [
        Positioned.fill(child: map),
        const Positioned(left: 12, top: 12, child: _HistoryLegend()),
        if (_selectedSighting != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: ListTile(
                title: Text(
                  formatReportDateTimeInBogota(_selectedSighting!['fechaHora']),
                ),
                subtitle: Text(
                  _selectedSighting!['descripcion']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDetail(_selectedSighting!),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryLegend extends StatelessWidget {
  const _HistoryLegend();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _HistoryLegendItem(color: Colors.red, label: 'Pérdida'),
            SizedBox(height: 3),
            _HistoryLegendItem(color: Colors.orange, label: 'Avistamiento'),
          ],
        ),
      ),
    );
  }
}

class _HistoryLegendItem extends StatelessWidget {
  const _HistoryLegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, size: 17, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
