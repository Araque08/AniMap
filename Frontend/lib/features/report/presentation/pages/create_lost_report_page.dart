import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/address_location_page.dart';
import '../../../../widgets/location_picker_page.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../../../widgets/geofence_validation_panel.dart';
import '../../data/device_location_service.dart';
import '../../data/geofence_service.dart';
import '../../data/geocoding_service.dart';
import '../../data/reports_service.dart';
import '../../../sighting/presentation/pages/sightings_history_page.dart';

typedef ReportsListLoader = Future<List<Map<String, dynamic>>> Function();
typedef ReportGeofenceChecker =
    Future<GeofenceCheckResult> Function(double lat, double lng);
typedef ReportCreator =
    Future<void> Function({
      required int mascotaId,
      required String descripcion,
      required bool mostrarContacto,
      required Map<String, dynamic> ubicacion,
    });
typedef ReportUpdater =
    Future<void> Function({
      required int reportId,
      required String descripcion,
      required bool mostrarContacto,
      Map<String, dynamic>? ubicacion,
    });
typedef ReportLocationPicker =
    Future<LatLng?> Function(
      BuildContext context,
      LatLng initialPosition,
      LatLng? selectedPosition,
    );
typedef ReportAddressPicker =
    Future<AddressLocationSelection?> Function(
      BuildContext context,
      String? initialAddress,
    );

class CreateLostReportPage extends StatefulWidget {
  const CreateLostReportPage({
    super.key,
    this.petsLoader,
    this.reportsLoader,
    this.locationLoader,
    this.locationPicker,
    this.addressPicker,
    this.geofenceChecker,
    this.reportCreator,
    this.reportUpdater,
  });

  final ReportsListLoader? petsLoader;
  final ReportsListLoader? reportsLoader;
  final Future<DeviceLocation> Function()? locationLoader;
  final ReportLocationPicker? locationPicker;
  final ReportAddressPicker? addressPicker;
  final ReportGeofenceChecker? geofenceChecker;
  final ReportCreator? reportCreator;
  final ReportUpdater? reportUpdater;

  @override
  State<CreateLostReportPage> createState() => _CreateLostReportPageState();
}

class _CreateLostReportPageState extends State<CreateLostReportPage> {
  static const _green = Color(0xFF3F9568);
  static const _darkText = Color(0xFF344955);
  static const _initialPosition = LatLng(4.6569, -74.1095);

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _referenceController = TextEditingController();

  List<Map<String, dynamic>> _pets = const [];
  List<Map<String, dynamic>> _reports = const [];
  int? _selectedPetId;
  int? _editingReportId;
  LatLng? _selectedLocation;
  double? _accuracy;
  String? _locationMethod;
  String? _validatedAddress;
  String? _placeId;
  bool _showContact = false;
  bool _showMyReports = false;
  bool _loading = true;
  bool _saving = false;
  bool _gettingGps = false;
  GeofenceValidationState _geofenceState = GeofenceValidationState.idle;
  String? _geofenceMode;
  bool _locationChanged = false;
  bool _baselineReady = false;
  String _baselineSignature = '';
  bool _submitted = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool keepSelection = false}) async {
    final hadUnsavedChanges = _hasUnsavedChanges;
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        (widget.petsLoader ?? ReportsService.getReportablePets)(),
        (widget.reportsLoader ?? ReportsService.getMyReports)(),
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
      if (!hadUnsavedChanges) _captureBaseline();
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

  List<Map<String, dynamic>> get _availablePets => _pets
      .where((pet) => pet['tieneReporteActivo'] != true)
      .toList(growable: false);

  List<Map<String, dynamic>> get _unavailablePets => _pets
      .where((pet) => pet['tieneReporteActivo'] == true)
      .toList(growable: false);

  Map<String, dynamic>? get _selectedPet {
    for (final pet in _pets) {
      if (pet['id'] == _selectedPetId) return pet;
    }
    return null;
  }

  AddressLocationSelection? get _currentAddressSelection {
    final location = _selectedLocation;
    final address = _validatedAddress;
    final placeId = _placeId;
    if (_locationMethod != 'DIRECCION' ||
        location == null ||
        address == null ||
        placeId == null ||
        !geofenceStateAllowsSubmit(_geofenceState)) {
      return null;
    }
    final warning = _geofenceState == GeofenceValidationState.outsideWarning;
    return AddressLocationSelection(
      formattedAddress: address,
      lat: location.latitude,
      lng: location.longitude,
      placeId: placeId,
      inside: !warning,
      allowed: true,
      mode: _geofenceMode ?? (warning ? 'WARN' : 'ENFORCE'),
    );
  }

  Map<String, dynamic> _locationPayload() {
    final location = _selectedLocation!;
    return {
      'metodo': _locationMethod!,
      'lat': location.latitude,
      'lng': location.longitude,
      'precisionM': _locationMethod == 'GPS' ? _accuracy : null,
      'direccion': _locationMethod == 'DIRECCION'
          ? _validatedAddress
          : (_referenceController.text.trim().isEmpty
                ? null
                : _referenceController.text.trim()),
      'placeId': _locationMethod == 'DIRECCION' ? _placeId : null,
    };
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _gettingGps = true);
    try {
      final location =
          await (widget.locationLoader ??
              DeviceLocationService.getCurrentLocation)();
      final position = LatLng(location.latitude, location.longitude);
      if (!mounted) return;
      setState(() {
        _selectedLocation = position;
        _accuracy = location.accuracy;
        _locationMethod = 'GPS';
        _validatedAddress = null;
        _placeId = null;
        _locationChanged = true;
      });
      await _validateSelectedLocation();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _gettingGps = false);
    }
  }

  Future<void> _chooseMapLocation() async {
    final initial = _selectedLocation ?? _initialPosition;
    final position = widget.locationPicker == null
        ? await Navigator.push<LatLng>(
            context,
            MaterialPageRoute(
              builder: (_) => LocationPickerPage(
                initialPosition: initial,
                selectedPosition: _selectedLocation,
                title: 'Ubicación de la pérdida',
              ),
            ),
          )
        : await widget.locationPicker!(context, initial, _selectedLocation);
    if (!mounted || position == null) return;
    setState(() {
      _selectedLocation = position;
      _accuracy = null;
      _locationMethod = 'MAPA';
      _validatedAddress = null;
      _placeId = null;
      _locationChanged = true;
    });
    await _validateSelectedLocation();
  }

  Future<void> _chooseAddressLocation() async {
    final selection = widget.addressPicker == null
        ? await Navigator.push<AddressLocationSelection>(
            context,
            MaterialPageRoute(
              builder: (_) => AddressLocationPage(
                initialAddress: _validatedAddress,
                initialSelection: _currentAddressSelection,
              ),
            ),
          )
        : await widget.addressPicker!(context, _validatedAddress);
    if (!mounted || selection == null) return;
    setState(() {
      _selectedLocation = LatLng(selection.lat, selection.lng);
      _accuracy = null;
      _locationMethod = 'DIRECCION';
      _validatedAddress = selection.formattedAddress;
      _placeId = selection.placeId;
      _locationChanged = true;
      _geofenceState = geofenceStateFor(
        GeofenceCheckResult(
          inside: selection.inside,
          allowed: selection.allowed,
          mode: selection.mode,
          areaName: 'Salitre Occidental',
        ),
      );
      _geofenceMode = selection.mode;
    });
  }

  Future<bool> _validateSelectedLocation() async {
    final location = _selectedLocation;
    if (location == null) return false;
    setState(() => _geofenceState = GeofenceValidationState.checking);
    try {
      final result = await (widget.geofenceChecker ?? GeofenceService.check)(
        location.latitude,
        location.longitude,
      );
      if (!mounted) return false;
      setState(() {
        _geofenceState = geofenceStateFor(result);
        _geofenceMode = result.mode;
      });
      return result.allowed;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _geofenceState = GeofenceValidationState.networkError;
      });
      return false;
    }
  }

  void _changeLocation() {
    setState(() {
      _selectedLocation = null;
      _locationMethod = null;
      _accuracy = null;
      _validatedAddress = null;
      _placeId = null;
      _locationChanged = true;
      _geofenceState = GeofenceValidationState.idle;
      _geofenceMode = null;
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
    final mustValidate = _editingReportId == null || _locationChanged;
    if (mustValidate && !geofenceStateAllowsSubmit(_geofenceState)) {
      final allowed = await _validateSelectedLocation();
      if (!allowed) return;
    }

    setState(() => _saving = true);
    try {
      if (_editingReportId == null) {
        await (widget.reportCreator ?? ReportsService.createReport)(
          mascotaId: _selectedPetId!,
          descripcion: _descriptionController.text,
          mostrarContacto: _showContact,
          ubicacion: _locationPayload(),
        );
        _showMessage('Reporte de pérdida creado correctamente.');
      } else {
        await (widget.reportUpdater ?? ReportsService.updateReport)(
          reportId: _editingReportId!,
          descripcion: _descriptionController.text,
          mostrarContacto: _showContact,
          ubicacion: _locationChanged ? _locationPayload() : null,
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
      final method = location['metodo']?.toString() ?? 'MAPA';
      if (method == 'DIRECCION') {
        _validatedAddress = location['direccion']?.toString();
        _placeId = location['placeId']?.toString();
        _referenceController.clear();
      } else {
        _validatedAddress = null;
        _placeId = null;
        _referenceController.text = location['direccion']?.toString() ?? '';
      }
      _showContact = report['mostrarContacto'] == true;
      _locationMethod = method;
      _accuracy = (location['precisionM'] as num?)?.toDouble();
      _selectedLocation = LatLng(lat, lng);
      _locationChanged = false;
      _geofenceState = GeofenceValidationState.idle;
      _geofenceMode = null;
      _showMyReports = false;
    });
    _submitted = false;
    _captureBaseline();
  }

  void _resetForm() {
    _descriptionController.clear();
    _referenceController.clear();
    _editingReportId = null;
    _selectedPetId = _firstAvailablePetId(_pets);
    _selectedLocation = null;
    _accuracy = null;
    _locationMethod = null;
    _validatedAddress = null;
    _placeId = null;
    _locationChanged = false;
    _geofenceState = GeofenceValidationState.idle;
    _geofenceMode = null;
    _showContact = false;
    _submitted = false;
    _captureBaseline();
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
      _showMessage('Reporte finalizado. La mascota volvió a estar activa.');
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

  String _currentFormSignature() => [
    _editingReportId,
    _selectedPetId,
    _descriptionController.text,
    _referenceController.text,
    _showContact,
    _selectedLocation?.latitude,
    _selectedLocation?.longitude,
    _locationMethod,
    _accuracy,
    _validatedAddress,
    _placeId,
  ].join('\u001f');

  bool get _hasUnsavedChanges =>
      !_submitted &&
      _baselineReady &&
      _currentFormSignature() != _baselineSignature;

  void _captureBaseline() {
    _baselineSignature = _currentFormSignature();
    _baselineReady = true;
  }

  Future<bool> _confirmDiscard([int? _]) async {
    if (!_hasUnsavedChanges) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Salir sin guardar?'),
            content: const Text('Los cambios realizados se perderán.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salir'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _goToReportSelector() {
    Navigator.pushNamedAndRemoveUntil(context, '/create-report', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _confirmDiscard() && context.mounted) {
          setState(() => _allowPop = true);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
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
        bottomNavigationBar: BottomMenuAnimap(
          currentIndex: 1,
          onBeforeNavigate: _confirmDiscard,
          onReportTap: _goToReportSelector,
        ),
      ),
    );
  }

  Widget _sectionSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
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
    if (_editingReportId == null && _availablePets.isEmpty) {
      return _noAvailablePets();
    }
    final selectablePets = _editingReportId == null
        ? _availablePets
        : _pets.where((item) => item['id'] == _selectedPetId).toList();
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
                isExpanded: true,
                key: ValueKey(
                  'pet-${_selectedPetId ?? 'none'}-$_editingReportId',
                ),
                initialValue: _selectedPetId,
                decoration: const InputDecoration(
                  labelText: 'Mascota',
                  border: OutlineInputBorder(),
                ),
                items: selectablePets.map((item) {
                  final race = item['raza'] == null ? '' : ' · ${item['raza']}';
                  return DropdownMenuItem<int>(
                    value: item['id'] as int,
                    child: Text(
                      '${item['nombre']} — ${item['especie']}$race',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                key: const ValueKey('lost-report-description'),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final gpsButton = OutlinedButton.icon(
                    key: const ValueKey('lost-report-use-gps'),
                    onPressed: _gettingGps ? null : _useCurrentLocation,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _locationMethod == 'GPS'
                          ? _green
                          : Colors.white,
                      foregroundColor: _locationMethod == 'GPS'
                          ? Colors.white
                          : _green,
                      side: const BorderSide(color: _green, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: _gettingGps
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: const Text('Usar GPS'),
                  );
                  final mapButton = OutlinedButton.icon(
                    key: const ValueKey('lost-report-use-map'),
                    onPressed: _chooseMapLocation,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _locationMethod == 'MAPA'
                          ? _green
                          : Colors.white,
                      foregroundColor: _locationMethod == 'MAPA'
                          ? Colors.white
                          : _green,
                      side: const BorderSide(color: _green, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Elegir en mapa'),
                  );
                  final addressButton = OutlinedButton.icon(
                    key: const ValueKey('lost-report-use-address'),
                    onPressed: _chooseAddressLocation,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _locationMethod == 'DIRECCION'
                          ? _green
                          : Colors.white,
                      foregroundColor: _locationMethod == 'DIRECCION'
                          ? Colors.white
                          : _green,
                      side: const BorderSide(color: _green, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: const Text('Ingresar dirección'),
                  );
                  if (constraints.maxWidth < 600) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        gpsButton,
                        const SizedBox(height: 8),
                        mapButton,
                        const SizedBox(height: 8),
                        addressButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: gpsButton),
                      const SizedBox(width: 10),
                      Expanded(child: mapButton),
                      const SizedBox(width: 10),
                      Expanded(child: addressButton),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7F3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFB7CDBD)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedLocation == null
                          ? Icons.location_off_outlined
                          : Icons.location_on,
                      color: _green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedLocation == null
                            ? 'Aún no has seleccionado una ubicación.'
                            : _locationMethod == 'DIRECCION'
                            ? _validatedAddress ?? 'Dirección validada'
                            : '$_locationMethod · '
                                  '${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                                  '${_selectedLocation!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(color: Color(0xFF64756B)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedLocation == null
                    ? 'Usa GPS, mapa o una dirección validada para indicar el punto exacto.'
                    : _locationMethod == 'DIRECCION'
                    ? 'Dirección validada: ${_validatedAddress ?? ''}'
                    : 'Ubicación seleccionada por $_locationMethod: '
                          '${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                          '${_selectedLocation!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(color: Color(0xFF64756B)),
              ),
              if (_selectedLocation != null) ...[
                const SizedBox(height: 10),
                GeofenceValidationPanel(
                  state: _geofenceState,
                  onChangeLocation: _changeLocation,
                  onRetry: _validateSelectedLocation,
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('lost-report-reference'),
                controller: _referenceController,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: 'Referencia adicional (opcional)',
                  hintText: 'Ej: frente al parque, portería del conjunto...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('save-lost-report'),
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

  Widget _noAvailablePets() {
    return ListView(
      key: const Key('no-available-pets'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 54, 22, 30),
      children: [
        const Icon(Icons.pets_outlined, size: 72, color: Color(0xFF8FA89A)),
        const SizedBox(height: 18),
        const Text(
          'No tienes mascotas disponibles para reportar.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        if (_unavailablePets.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Ya tienen un reporte activo:',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ..._unavailablePets.map(
            (pet) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${pet['nombre']} · ${pet['especie']}'
                '${pet['raza'] == null ? '' : ' · ${pet['raza']}'}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => setState(() => _showMyReports = true),
          icon: const Icon(Icons.list_alt),
          label: const Text('Ver mis reportes'),
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
    final reference = location['referencia']?.toString();
    final isAddress = location['metodo'] == 'DIRECCION';
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
              isAddress && location['direccion'] != null
                  ? 'Ubicación: ${location['direccion']}'
                  : 'Ubicación: ${location['metodo']} · '
                        '${location['lat']}, ${location['lng']}',
              style: const TextStyle(color: Color(0xFF64756B)),
            ),
            if (reference?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                'Referencia: $reference',
                style: const TextStyle(color: Color(0xFF64756B)),
              ),
            ],
            const Divider(height: 24),
            ReportSightingsSummary(
              reportId: report['id'] as int,
              count: (report['avistamientosCount'] as num?)?.toInt() ?? 0,
              onOpen: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SightingsHistoryPage(reportId: report['id'] as int),
                ),
              ),
            ),
            if (active) ...[
              const Divider(height: 16),
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
