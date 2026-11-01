import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../config/api_config.dart';
import '../../../map/presentation/pages/map_page.dart';
import '../../../pet/data/pet_image_selection.dart';
import '../../../sighting/presentation/pages/sightings_history_page.dart';
import '../../data/report_datetime.dart';
import '../../data/reports_service.dart';

/// Carga el reporte privado y reutiliza el detalle visual del mapa.
class OwnReportDetailPage extends StatefulWidget {
  const OwnReportDetailPage({
    super.key,
    required this.reportId,
    this.loader,
    this.mapBuilder,
    this.historyBuilder,
  });

  final int reportId;
  final Future<OwnReportDetails> Function(int)? loader;
  final ReportMapBuilder? mapBuilder;
  final Widget Function(int)? historyBuilder;

  @override
  State<OwnReportDetailPage> createState() => _OwnReportDetailPageState();
}

class _OwnReportDetailPageState extends State<OwnReportDetailPage> {
  late Future<OwnReportDetails> _details;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OwnReportDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportId != widget.reportId) _load();
  }

  void _load() {
    _details = (widget.loader ?? ReportsService.getOwnReportDetails)(
      widget.reportId,
    ).timeout(const Duration(seconds: 20));
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String? _privatePhoto(dynamic photo) {
    if (photo is! Map || _text(photo['url']).isEmpty) return null;
    final base = ApiConfig.current.baseUri;
    final path = Uri.tryParse(_text(photo['url']));
    if (path == null) return null;
    final uri = Uri.parse('${base.origin}/').resolveUri(path);
    // El Bearer solo se envía al endpoint privado de imágenes de AniMap.
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.origin != base.origin ||
        uri.userInfo.isNotEmpty ||
        !uri.path.startsWith('${base.path}/pets/images/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri.toString();
  }

  MapReport _asMapReport(OwnReportDetails details) {
    final report = details.report;
    final basicPet = report['mascota'];
    final location = report['ubicacion'];
    if (report['id'] != widget.reportId ||
        basicPet is! Map ||
        location is! Map ||
        !['ACTIVO', 'FINALIZADO'].contains(report['estado'])) {
      throw ReportsException('El reporte no está disponible.');
    }
    final lat = double.tryParse(_text(location['lat']));
    final lng = double.tryParse(_text(location['lng']));
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      throw ReportsException('El reporte no tiene una ubicación válida.');
    }
    final photos = <String>[];
    if (basicPet['estado'] != 'INACTIVA') {
      for (final photo in principalImageFirst(
        details.photos,
        (photo) => photo['esPrincipal'] == true,
      )) {
        final url = _privatePhoto(photo);
        if (url != null && !photos.contains(url)) photos.add(url);
      }
      final main = _privatePhoto(basicPet['fotoPrincipal']);
      if (photos.isEmpty && main != null) photos.add(main);
    }
    final address = location['metodo'] == 'DIRECCION'
        ? _text(location['direccion'])
        : '';
    final species = _text(basicPet['especie']);
    final breed = _text(basicPet['raza']);
    return MapReport(
      id: 'lost_${report['id']}',
      title: 'Reporte de pérdida',
      petName: _text(basicPet['nombre']),
      details: [species, breed].where((value) => value.isNotEmpty).join(' · '),
      species: species,
      color: _text(details.pet['color']),
      location: address.isEmpty ? 'Punto marcado en el mapa' : address,
      reference: _text(location['referencia']),
      description: _text(report['descripcion']).isEmpty
          ? 'Sin descripción adicional.'
          : _text(report['descripcion']),
      dateText: formatReportDateTimeInBogota(report['creadoEn']),
      createdDateText: formatReportDateTimeInBogota(report['creadoEn']),
      closedDateText: formatReportDateTimeInBogota(report['cerradoEn']),
      occurredAt: reportDateTimeInBogota(report['creadoEn']),
      imageUrl: photos.isEmpty ? null : photos.first,
      imageUrls: photos,
      position: LatLng(lat, lng),
      type: report['estado'] == 'FINALIZADO'
          ? ReportType.found
          : ReportType.lost,
      isOwner: true,
      showContact: false,
      ownerName: '',
      ownerPhone: '',
      ownerEmail: '',
    );
  }

  Map<String, String> _petInfo(Map<String, dynamic> pet) {
    final age = pet['edad_aprox'];
    final unit = pet['unidad_edad'];
    return {
      if (_text(pet['color']).isNotEmpty) 'Color': _text(pet['color']),
      if (age != null && ['MESES', 'ANIOS'].contains(unit))
        'Edad aproximada':
            '$age ${unit == 'MESES' ? (age == 1 ? 'mes' : 'meses') : (age == 1 ? 'año' : 'años')}',
      if (['MACHO', 'HEMBRA'].contains(pet['sexo'])) 'Sexo': _text(pet['sexo']),
      if (_text(pet['observaciones']).isNotEmpty)
        'Observaciones de la mascota': _text(pet['observaciones']),
    };
  }

  Widget _status({String? error}) => Scaffold(
    appBar: AppBar(title: const Text('Detalle del reporte')),
    body: Center(
      child: error == null
          ? const CircularProgressIndicator()
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(_load),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<OwnReportDetails>(
    future: _details,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return _status();
      if (snapshot.hasError || !snapshot.hasData) {
        return _status(
          error: snapshot.error is ReportsException
              ? snapshot.error.toString()
              : 'No se pudo cargar el reporte. Intenta nuevamente.',
        );
      }
      final details = snapshot.data!;
      try {
        return ReportDetailPage(
          report: _asMapReport(details),
          mapBuilder: widget.mapBuilder,
          imageHeaders: ReportsService.imageHeaders,
          petInfo: _petInfo(details.pet),
          sightingsSummary: ReportSightingsSummary(
            reportId: widget.reportId,
            count: (details.report['avistamientosCount'] as num?)?.toInt() ?? 0,
            onOpen: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    widget.historyBuilder?.call(widget.reportId) ??
                    SightingsHistoryPage(reportId: widget.reportId),
              ),
            ),
          ),
        );
      } on ReportsException catch (error) {
        return _status(error: error.message);
      }
    },
  );
}
