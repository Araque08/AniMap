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
import 'own_report_detail_page.dart';
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
    this.reportDetailBuilder,
    this.reportCloser,
    this.reportHistoryBuilder,
  });

  final ReportsListLoader? petsLoader;
  final ReportsListLoader? reportsLoader;
  final Future<DeviceLocation> Function()? locationLoader;
  final ReportLocationPicker? locationPicker;
  final ReportAddressPicker? addressPicker;
  final ReportGeofenceChecker? geofenceChecker;
  final ReportCreator? reportCreator;
  final ReportUpdater? reportUpdater;
  final Widget Function(int reportId)? reportDetailBuilder;
  final Future<void> Function(int reportId)? reportCloser;
  final Widget Function(int reportId)? reportHistoryBuilder;

  @override
  State<CreateLostReportPage> createState() => _CreateLostReportPageState();
}

class _CreateLostReportPageState extends State<CreateLostReportPage> {
  static const _green = Color(0xFF3F9568);
  static const _softGreen = Color(0xFFE9F6EE);
  static const _border = Color(0xFFDCE7E0);
  static const _muted = Color(0xFF66776E);
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
    if (_saving) return;
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
      if (!mounted) return;
      setState(() {
        _resetForm();
        _showMyReports = true;
      });
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
      await (widget.reportCloser ?? ReportsService.closeReport)(
        report['id'] as int,
      );
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

  void _goToReportSearch() {
    Navigator.pushNamedAndRemoveUntil(context, '/search-reports', (_) => false);
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
        backgroundColor: const Color(0xFFF7FAF8),
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
          onReportTap: _goToReportSearch,
        ),
      ),
    );
  }

  Widget _sectionSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFE1F4E9),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Expanded(child: _tabButton(
            label: 'Reportar', icon: Icons.add_circle_outline,
            selected: !_showMyReports,
            onTap: () => _switchSection(false),
          )),
          Expanded(child: _tabButton(
            label: 'Mis reportes', icon: Icons.list_alt_rounded,
            selected: _showMyReports,
            onTap: () => _switchSection(true),
          )),
        ]),
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? _green : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 19, color: selected ? Colors.white : _darkText),
            const SizedBox(width: 7),
            Flexible(child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : _darkText),
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _switchSection(bool showReports) async {
    if (showReports == _showMyReports) return;
    if (showReports && _hasUnsavedChanges) {
      final discard = await _confirmDiscard();
      if (!discard || !mounted) return;
      setState(() {
        _resetForm();
        _showMyReports = true;
      });
      return;
    }
    if (mounted) setState(() => _showMyReports = showReports);
  }

  Widget _panel({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: const [BoxShadow(
          color: Color(0x090E4026), blurRadius: 16, offset: Offset(0, 5),
        )],
      ),
      child: child,
    );
  }

  Widget _sectionHeading(IconData icon, String title, String detail) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 39, height: 39,
        decoration: BoxDecoration(color: _softGreen,
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: _green, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800, color: _darkText)),
          const SizedBox(height: 3),
          Text(detail, style: const TextStyle(
              fontSize: 12.5, height: 1.35, color: _muted)),
        ],
      )),
    ]);
  }

  InputDecoration _inputStyle({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: const Color(0xFFFBFCFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _green, width: 1.8)),
    );
  }

  // Abre el registro existente de mascotas y actualiza esta pantalla
  // al regresar, sin perder la información que ya se haya diligenciado.
  Future<void> _registerPetFromReport() async {
    final previousIds = _pets.map((pet) => pet['id']).toSet();
    try {
      await Navigator.pushNamed(context, '/register-pet');
      if (!mounted) return;

      await _loadData(keepSelection: true);
      if (!mounted) return;

      // Si se creó una mascota nueva, dejar su tarjeta seleccionada.
      final newPets = _availablePets
          .where((pet) => !previousIds.contains(pet['id']))
          .toList();
      if (newPets.isNotEmpty) {
        setState(() => _selectedPetId = newPets.last['id'] as int);
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Widget _registerPetButton() {
    return OutlinedButton.icon(
      key: const ValueKey('register-pet-from-report'),
      onPressed: _registerPetFromReport,
      style: OutlinedButton.styleFrom(
        foregroundColor: _green,
        side: const BorderSide(color: _green),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
      ),
      icon: const Icon(Icons.add_circle_outline_rounded, size: 21),
      label: const Text('Registrar otra mascota'),
    );
  }

  Widget _reportForm() {
    if (_editingReportId == null && _availablePets.isEmpty) {
      return _noAvailablePets();
    }
    final selectablePets = _editingReportId == null
        ? _availablePets
        : _pets.where((item) => item['id'] == _selectedPetId).toList();

    return Form(
      key: _formKey,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
        children: [
          Text(
            _editingReportId == null
                ? 'Reportar mascota perdida' : 'Editar reporte activo',
            style: const TextStyle(fontSize: 25, height: 1.13,
                fontWeight: FontWeight.w800, color: _darkText),
          ),
          const SizedBox(height: 9),
          Text(
            _editingReportId == null
                ? 'Completa la información para ayudar a encontrar a tu mascota.'
                : 'Actualiza los datos de tu reporte activo.',
            style: const TextStyle(color: _muted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          _panel(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeading(Icons.pets_rounded, 'Tu mascota',
                  'Selecciona la mascota que deseas reportar.'),
              const SizedBox(height: 16),
              ...selectablePets.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _selectablePetCard(item),
              )),
              if (_editingReportId == null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: _registerPetButton(),
                ),
              ],
              if (_selectedPetId == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Selecciona una mascota para continuar.',
                    style: TextStyle(color: Color(0xFFB3261E), fontSize: 13),
                  ),
                ),
            ],
          )),
          const SizedBox(height: 14),
          _panel(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeading(Icons.edit_note_rounded, 'Descripción',
                  'Incluye rasgos, accesorios o detalles que ayuden a identificarla.'),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('lost-report-description'),
                controller: _descriptionController,
                maxLength: 1000,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: _inputStyle(
                    label: 'Descripción y señas útiles',
                    hint: 'Ej.: lleva collar rojo y tiene una mancha blanca...'),
              ),
            ],
          )),
          const SizedBox(height: 14),
          _panel(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeading(Icons.shield_outlined, 'Privacidad del contacto',
                  'Decide si autorizas mostrar tu teléfono en el reporte público.'),
              const SizedBox(height: 9),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _showContact,
                activeColor: _green,
                title: const Text('Permitir contacto',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _darkText)),
                subtitle: Text(_showContact
                    ? 'Tu teléfono será visible para quienes consulten el reporte.'
                    : 'Tu teléfono no se mostrará en el reporte público.',
                    style: const TextStyle(fontSize: 12.5, color: _muted)),
                onChanged: (value) => setState(() => _showContact = value),
              ),
            ],
          )),
          const SizedBox(height: 14),
          _panel(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeading(Icons.location_on_outlined,
                  'Última ubicación conocida',
                  'Indica el lugar donde fue vista por última vez.'),
              const SizedBox(height: 16),
              _locationOption(Icons.my_location_rounded, 'Usar GPS',
                  _locationMethod == 'GPS', _gettingGps ? null : _useCurrentLocation,
                  loading: _gettingGps),
              const SizedBox(height: 9),
              _locationOption(Icons.map_outlined, 'Elegir en mapa',
                  _locationMethod == 'MAPA', _chooseMapLocation),
              const SizedBox(height: 14),
              _locationSummary(),
              if (_selectedLocation != null) ...[
                const SizedBox(height: 12),
                GeofenceValidationPanel(
                  state: _geofenceState,
                  onChangeLocation: _changeLocation,
                  onRetry: _validateSelectedLocation,
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('lost-report-reference'),
                controller: _referenceController,
                maxLength: 255,
                textCapitalization: TextCapitalization.sentences,
                decoration: _inputStyle(
                    label: 'Punto de referencia (opcional)',
                    hint: 'Ej.: frente al parque o cerca de la portería'),
              ),
            ],
          )),
          const SizedBox(height: 20),
          SizedBox(height: 54, child: FilledButton.icon(
            key: const ValueKey('save-lost-report'),
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: _saving
                ? const SizedBox.square(dimension: 19,
                child: CircularProgressIndicator(strokeWidth: 2,
                    color: Colors.white))
                : Icon(_editingReportId == null
                ? Icons.campaign_outlined : Icons.save_outlined),
            label: Text(_saving ? 'Guardando...'
                : _editingReportId == null ? 'Crear reporte' : 'Guardar cambios',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          )),
          if (_editingReportId != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(_resetForm),
              child: const Text('Cancelar edición'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _locationOption(IconData icon, String title, bool selected,
      VoidCallback? onTap, {bool loading = false}) {
    return Material(
      color: selected ? _softGreen : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 49,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? _green : _border,
                width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            loading
                ? const SizedBox.square(dimension: 19,
                child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, color: _green, size: 21),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(
                fontWeight: FontWeight.w700, color: _darkText))),
            Icon(selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: selected ? _green : _muted, size: 21),
          ]),
        ),
      ),
    );
  }

  Widget _locationSummary() {
    final hasLocation = _selectedLocation != null;
    final title = !hasLocation
        ? 'Ubicación pendiente'
        : _locationMethod == 'DIRECCION'
        ? (_validatedAddress ?? 'Dirección seleccionada')
        : '${_locationMethod == 'GPS' ? 'Ubicación GPS' : 'Punto en el mapa'} seleccionado';
    final detail = !hasLocation
        ? 'Usa el GPS o marca el lugar en el mapa.'
        : _locationMethod == 'DIRECCION'
        ? 'Dirección registrada para este reporte.'
        : _locationMethod == 'GPS'
        ? 'Ubicación obtenida correctamente. Puedes continuar con el reporte.'
        : 'Punto guardado correctamente. Puedes continuar con el reporte.';
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: hasLocation ? _softGreen : const Color(0xFFF7F9F7),
        border: Border.all(color: hasLocation
            ? const Color(0xFFB6DFC5) : _border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(hasLocation ? Icons.check_circle_outline_rounded
            : Icons.info_outline_rounded,
            color: hasLocation ? _green : _muted, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
                fontWeight: FontWeight.w700, color: _darkText)),
            const SizedBox(height: 3),
            Text(detail, style: const TextStyle(
                fontSize: 12.5, color: _muted)),
          ],
        )),
      ]),
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
        _registerPetButton(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => setState(() => _showMyReports = true),
          icon: const Icon(Icons.list_alt),
          label: const Text('Ver mis reportes'),
        ),
      ],
    );
  }

  Widget _selectablePetCard(Map<String, dynamic> pet) {
    final id = pet['id'] as int;
    final selected = _selectedPetId == id;
    final editing = _editingReportId != null;
    final photo = pet['fotoPrincipal'] is Map
        ? Map<String, dynamic>.from(pet['fotoPrincipal'] as Map)
        : null;

    return Material(
      color: selected ? _softGreen : const Color(0xFFFBFCFA),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('select-pet-$id'),
        borderRadius: BorderRadius.circular(16),
        onTap: editing ? null : () => setState(() => _selectedPetId = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _green : _border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(children: [
            _petPhoto(photo, 60),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${pet['nombre']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w800, color: _darkText)),
                const SizedBox(height: 4),
                Text('${pet['especie']}'
                    '${pet['raza'] == null ? '' : ' · ${pet['raza']}'}',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 13)),
                if (selected) ...[
                  const SizedBox(height: 5),
                  const Text('Seleccionada',
                      style: TextStyle(color: _green,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ],
            )),
            const SizedBox(width: 8),
            Icon(selected ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
                color: selected ? _green : const Color(0xFF9CAC9F),
                size: 25),
          ]),
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
      child: InkWell(
        key: ValueKey('own-report-card-${report['id']}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
            widget.reportDetailBuilder?.call(report['id'] as int) ??
                OwnReportDetailPage(reportId: report['id'] as int),
          ),
        ),
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
                    : location['metodo'] == 'GPS'
                    ? 'Ubicación: registrada mediante GPS'
                    : 'Ubicación: seleccionada en el mapa',
                style: const TextStyle(color: Color(0xFF64756B)),
              ),
              if (reference?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  'Señas: $reference',
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
                    widget.reportHistoryBuilder?.call(
                      report['id'] as int,
                    ) ??
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
      ),
    );
  }


  Widget _petPhoto(Map<String, dynamic>? photo, double size) {
    final originalUrl = ReportsService.imageUrl(photo);

    if (originalUrl == null || originalUrl.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        child: const Icon(Icons.pets),
      );
    }

    final uri = Uri.tryParse(originalUrl);

    // Solo optimizamos las imágenes privadas de mascotas
    // que ya cuentan con el endpoint de miniaturas.
    final useThumbnail =
        uri != null &&
            RegExp(r'^/api/pets/images/[^/]+$').hasMatch(uri.path);

    final imageUrl = useThumbnail
        ? uri.replace(path: '${uri.path}/thumbnail').toString()
        : originalUrl;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeSize = (size * pixelRatio).ceil();

    return ClipOval(
      child: Image.network(
        imageUrl,
        headers: ReportsService.imageHeaders,
        width: size,
        height: size,
        cacheWidth: decodeSize,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }

          return SizedBox.square(
            dimension: size,
            child: const ColoredBox(
              color: Color(0xFFDFF3E8),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF3F9568),
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return SizedBox.square(
            dimension: size,
            child: const ColoredBox(
              color: Color(0xFFDFF3E8),
              child: Icon(
                Icons.pets,
                color: Color(0xFF3F9568),
              ),
            ),
          );
        },
      ),
    );
  }

}
