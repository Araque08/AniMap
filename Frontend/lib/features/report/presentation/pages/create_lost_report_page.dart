import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../data/device_location_service.dart';
import '../../data/reports_service.dart';

class CreateLostReportPage extends StatefulWidget {
  const CreateLostReportPage({super.key});

  @override
  State<CreateLostReportPage> createState() => _CreateLostReportPageState();
}

class _CreateLostReportPageState extends State<CreateLostReportPage> {
  static const _green = Color(0xFF3F9568);
  static const _darkText = Color(0xFF344955);
  static const _initialPosition = LatLng(4.6569, -74.1095);

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();

  List<Map<String, dynamic>> _pets = const [];
  List<Map<String, dynamic>> _reports = const [];
  int? _selectedPetId;
  int? _editingReportId;
  LatLng? _selectedLocation;
  double? _accuracy;
  String _locationMethod = 'MAPA';
  bool _showContact = false;
  bool _showMyReports = false;
  bool _loading = true;
  bool _saving = false;
  bool _gettingGps = false;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool keepSelection = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ReportsService.getReportablePets(),
        ReportsService.getMyReports(),
      ]);
      if (!mounted) return;
      final pets = results[0];
      final reports = results[1];
      int? selectedId = keepSelection ? _selectedPetId : null;
      if (selectedId == null || !pets.any((pet) => pet['id'] == selectedId)) {
        selectedId = _firstAvailablePetId(pets);
      }
      setState(() {
        _pets = pets;
        _reports = reports;
        _selectedPetId = selectedId;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  int? _firstAvailablePetId(List<Map<String, dynamic>> pets) {
    for (final pet in pets) {
      if (pet['tieneReporteActivo'] != true) return pet['id'] as int?;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedPet {
    for (final pet in _pets) {
      if (pet['id'] == _selectedPetId) return pet;
    }
    return null;
  }

  Map<String, dynamic> _locationPayload() {
    final location = _selectedLocation!;
    return {
      'metodo': _locationMethod,
      'lat': location.latitude,
      'lng': location.longitude,
      'precisionM': _locationMethod == 'GPS' ? _accuracy : null,
      'direccion': _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      'placeId': null,
    };
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _gettingGps = true);
    try {
      final location = await DeviceLocationService.getCurrentLocation();
      final position = LatLng(location.latitude, location.longitude);
      if (!mounted) return;
      setState(() {
        _selectedLocation = position;
        _accuracy = location.accuracy;
        _locationMethod = 'GPS';
      });
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(position, 16),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _gettingGps = false);
    }
  }

  void _selectMapLocation(LatLng position) {
    setState(() {
      _selectedLocation = position;
      _accuracy = null;
      _locationMethod = 'MAPA';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_editingReportId == null && _selectedPetId == null) {
      _showMessage('Selecciona una mascota disponible.');
      return;
    }
    if (_selectedLocation == null) {
      _showMessage('Obtén tu ubicación GPS o selecciona un punto en el mapa.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_editingReportId == null) {
        await ReportsService.createReport(
          mascotaId: _selectedPetId!,
          descripcion: _descriptionController.text,
          mostrarContacto: _showContact,
          ubicacion: _locationPayload(),
        );
        _showMessage('Reporte de pérdida creado correctamente.');
      } else {
        await ReportsService.updateReport(
          reportId: _editingReportId!,
          descripcion: _descriptionController.text,
          mostrarContacto: _showContact,
          ubicacion: _locationPayload(),
        );
        _showMessage('Reporte actualizado correctamente.');
      }
      _resetForm();
      if (mounted) setState(() => _showMyReports = true);
      await _loadData();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startEdit(Map<String, dynamic> report) {
    if (report['estado'] != 'ACTIVO') return;
    final location = Map<String, dynamic>.from(report['ubicacion'] as Map);
    final pet = Map<String, dynamic>.from(report['mascota'] as Map);
    final lat = (location['lat'] as num).toDouble();
    final lng = (location['lng'] as num).toDouble();
    setState(() {
      _editingReportId = report['id'] as int;
      _selectedPetId = pet['id'] as int;
      _descriptionController.text = report['descripcion']?.toString() ?? '';
      _addressController.text = location['direccion']?.toString() ?? '';
      _showContact = report['mostrarContacto'] == true;
      _locationMethod = location['metodo']?.toString() ?? 'MAPA';
      _accuracy = (location['precisionM'] as num?)?.toDouble();
      _selectedLocation = LatLng(lat, lng);
      _showMyReports = false;
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
    );
  }

  void _resetForm() {
    _descriptionController.clear();
    _addressController.clear();
    _editingReportId = null;
    _selectedPetId = _firstAvailablePetId(_pets);
    _selectedLocation = null;
    _accuracy = null;
    _locationMethod = 'MAPA';
    _showContact = false;
  }

  Future<void> _closeReport(Map<String, dynamic> report) async {
    final pet = Map<String, dynamic>.from(report['mascota'] as Map);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar reporte'),
        content: Text(
          '¿Confirmas que ${pet['nombre']} fue encontrada? '
          'El reporte ya no podrá editarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ReportsService.closeReport(report['id'] as int);
      if (!mounted) return;
      _showMessage('Reporte finalizado. La mascota quedó como encontrada.');
      await _loadData();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) => _showMessage(error.toString());

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F4),
      drawer: const AniMapSideMenu(),
      body: Column(
        children: [
          const TopMenuAnimap(),
          _sectionSelector(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: _showMyReports ? _reportsList() : _reportForm(),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomMenuAnimap(currentIndex: 1),
    );
  }

  Widget _sectionSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.add),
            label: Text('Reportar'),
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.list),
            label: Text('Mis reportes'),
          ),
        ],
        selected: {_showMyReports},
        onSelectionChanged: (value) {
          setState(() => _showMyReports = value.first);
        },
      ),
    );
  }

  Widget _reportForm() {
    final pet = _selectedPet;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
      children: [
        Text(
          _editingReportId == null
              ? 'Reportar mascota perdida'
              : 'Editar reporte activo',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _darkText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _editingReportId == null
              ? 'Selecciona una de tus mascotas registradas y marca dónde fue vista por última vez.'
              : 'Actualiza la descripción o la ubicación del reporte.',
          style: const TextStyle(color: Color(0xFF64756B)),
        ),
        const SizedBox(height: 18),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey(
                  'pet-${_selectedPetId ?? 'none'}-$_editingReportId',
                ),
                initialValue: _selectedPetId,
                decoration: const InputDecoration(
                  labelText: 'Mascota',
                  border: OutlineInputBorder(),
                ),
                items: _pets.map((item) {
                  final unavailable =
                      item['tieneReporteActivo'] == true &&
                      item['id'] != _selectedPetId;
                  final race = item['raza'] == null ? '' : ' · ${item['raza']}';
                  final active = unavailable ? ' (con reporte activo)' : '';
                  return DropdownMenuItem<int>(
                    value: item['id'] as int,
                    enabled: !unavailable,
                    child: Text(
                      '${item['nombre']} — ${item['especie']}$race$active',
                    ),
                  );
                }).toList(),
                onChanged: _editingReportId != null
                    ? null
                    : (value) => setState(() => _selectedPetId = value),
                validator: (value) =>
                    value == null ? 'No hay una mascota disponible' : null,
              ),
              if (pet != null) ...[
                const SizedBox(height: 12),
                _petSummary(pet),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLength: 1000,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción y señas útiles',
                  hintText: 'Describe cómo reconocerla y dónde se perdió.',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showContact,
                activeThumbColor: _green,
                title: const Text('Autorizar contacto en este reporte'),
                subtitle: const Text(
                  'Si lo autorizas, el mapa público mostrará únicamente tu teléfono.',
                ),
                onChanged: (value) => setState(() => _showContact = value),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ubicación real',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _gettingGps ? null : _useCurrentLocation,
                      icon: _gettingGps
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('Usar GPS'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _locationMethod = 'MAPA'),
                      icon: const Icon(Icons.location_on_outlined),
                      label: const Text('Elegir en mapa'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 300,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFB7CDBD)),
                ),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedLocation ?? _initialPosition,
                    zoom: _selectedLocation == null ? 11 : 16,
                  ),
                  onMapCreated: (controller) => _mapController = controller,
                  onTap: _selectMapLocation,
                  markers: _selectedLocation == null
                      ? const {}
                      : {
                          Marker(
                            markerId: const MarkerId('report-location'),
                            position: _selectedLocation!,
                          ),
                        },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedLocation == null
                    ? 'Toca el mapa para indicar el punto exacto.'
                    : 'Ubicación seleccionada por $_locationMethod: '
                          '${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                          '${_selectedLocation!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(color: Color(0xFF64756B)),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _addressController,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: 'Referencia de dirección (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _editingReportId == null ? Icons.campaign : Icons.save,
                      ),
                label: Text(
                  _editingReportId == null
                      ? 'Crear reporte'
                      : 'Guardar cambios',
                ),
              ),
              if (_editingReportId != null)
                TextButton(
                  onPressed: () => setState(_resetForm),
                  child: const Text('Cancelar edición'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _petSummary(Map<String, dynamic> pet) {
    final photo = pet['fotoPrincipal'] is Map
        ? Map<String, dynamic>.from(pet['fotoPrincipal'] as Map)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _petPhoto(photo, 62),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pet['nombre']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${pet['especie']}'
                    '${pet['raza'] == null ? '' : ' · ${pet['raza']}'}',
                  ),
                  Text(
                    'Estado: ${pet['estado']}',
                    style: const TextStyle(color: _green),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportsList() {
    if (_reports.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.pets_outlined, size: 70, color: Color(0xFF8FA89A)),
          SizedBox(height: 12),
          Center(child: Text('Aún no tienes reportes de pérdida.')),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
      itemCount: _reports.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _reportCard(_reports[index]),
    );
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final pet = Map<String, dynamic>.from(report['mascota'] as Map);
    final location = Map<String, dynamic>.from(report['ubicacion'] as Map);
    final photo = pet['fotoPrincipal'] is Map
        ? Map<String, dynamic>.from(pet['fotoPrincipal'] as Map)
        : null;
    final active = report['estado'] == 'ACTIVO';
    final address = location['direccion']?.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _petPhoto(photo, 62),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pet['nombre']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${pet['especie']}'
                        '${pet['raza'] == null ? '' : ' · ${pet['raza']}'}',
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text('${report['estado']}'),
                  backgroundColor: active
                      ? const Color(0xFFFFE1DE)
                      : const Color(0xFFDFF3E8),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              report['descripcion']?.toString().isNotEmpty == true
                  ? report['descripcion'].toString()
                  : 'Sin descripción adicional.',
            ),
            const SizedBox(height: 6),
            Text(
              address?.isNotEmpty == true
                  ? '${location['metodo']} · $address'
                  : '${location['metodo']} · ${location['lat']}, ${location['lng']}',
              style: const TextStyle(color: Color(0xFF64756B)),
            ),
            if (active) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _startEdit(report),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _closeReport(report),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Encontrada'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _petPhoto(Map<String, dynamic>? photo, double size) {
    final url = ReportsService.imageUrl(photo);
    if (url == null) {
      return CircleAvatar(radius: size / 2, child: const Icon(Icons.pets));
    }
    return ClipOval(
      child: Image.network(
        url,
        headers: ReportsService.imageHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => SizedBox.square(
          dimension: size,
          child: const ColoredBox(
            color: Color(0xFFDFF3E8),
            child: Icon(Icons.pets, color: _green),
          ),
        ),
      ),
    );
  }
}
