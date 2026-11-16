import 'dart:typed_data';
import 'dart:math';
import '../../../auth/data/session_manager.dart';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../widgets/location_picker_page.dart';
import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/geofence_validation_panel.dart';
import '../../../../widgets/address_location_page.dart';
import '../../../pet/data/pet_image_selection.dart';
import '../../../report/data/device_location_service.dart';
import '../../../report/data/geofence_service.dart';
import '../../../report/data/geocoding_service.dart';
import '../../data/sightings_service.dart';

typedef LinkableReportsLoader = Future<List<Map<String, dynamic>>> Function();
typedef SightingCreator =
Future<Map<String, dynamic>> Function({
required String descripcion,
int? reportId,
required String metodo,
required double lat,
required double lng,
double? precisionM,
String? direccion,
String? placeId,
XFile? foto,
});
typedef SightingPhotoPicker =
Future<XFile?> Function({required ImageSource source});
typedef SightingMiniMapBuilder =
Widget Function(BuildContext context, LatLng position);
typedef SightingLocationPicker =
Future<LatLng?> Function(
    BuildContext context,
    LatLng initialPosition,
    LatLng? selectedPosition,
    );
typedef SightingGeofenceChecker =
Future<GeofenceCheckResult> Function(double lat, double lng);
typedef SightingAddressPicker =
Future<AddressLocationSelection?> Function(
    BuildContext context,
    String? initialAddress,
    );

class CreateSightingPage extends StatefulWidget {
  const CreateSightingPage({
    super.key,
    this.reporteInicialId,
    this.initialPhoto,
    this.reportsLoader,
    this.sightingCreator,
    this.locationLoader,
    this.photoPicker,
    this.miniMapBuilder,
    this.locationPicker,
    this.geofenceChecker,
    this.addressPicker,
  });

  final int? reporteInicialId;
  final XFile? initialPhoto;
  final LinkableReportsLoader? reportsLoader;
  final SightingCreator? sightingCreator;
  final Future<DeviceLocation> Function()? locationLoader;
  final SightingPhotoPicker? photoPicker;
  final SightingMiniMapBuilder? miniMapBuilder;
  final SightingLocationPicker? locationPicker;
  final SightingGeofenceChecker? geofenceChecker;
  final SightingAddressPicker? addressPicker;

  @override
  State<CreateSightingPage> createState() => _CreateSightingPageState();
}

class _CreateSightingPageState extends State<CreateSightingPage> {
  static const _green = Color(0xFF3F9568);
  static const _initialPosition = LatLng(4.6569, -74.1095);
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _imagePicker = ImagePicker();

  List<Map<String, dynamic>> _reports = const [];
  bool _loadingReports = true;
  bool _linked = false;
  int? _selectedReportId;
  LatLng? _selectedLocation;
  String? _locationMethod;
  double? _accuracy;
  String? _validatedAddress;
  String? _placeId;
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _locationConfirmed = false;
  bool _shareContact = false;
  late final String _requestId;
  int? _formGeneration;
  bool _gettingGps = false;
  bool _saving = false;
  bool _submitted = false;
  bool _allowPop = false;
  GeofenceValidationState _geofenceState = GeofenceValidationState.idle;
  String? _geofenceMode;

  @override
  void initState() {
    super.initState();
    _requestId = _newRequestId();
    _formGeneration = SessionManager.instance.authenticatedSessionGeneration;
    _linked = widget.reporteInicialId != null;
    _loadReports();
    if (widget.initialPhoto case final photo?) _setPhoto(photo);
  }

  static String _newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    try {
      final reports =
      await (widget.reportsLoader ?? SightingsService.getLinkableReports)();

      if (!mounted) return;

      final reporteInicial = widget.reporteInicialId;

      final existeReporte =
          reporteInicial != null &&
              reports.any(
                    (reporte) =>
                int.tryParse(reporte['id'].toString()) == reporteInicial,
              );

      setState(() {
        _reports = reports;

        if (reporteInicial != null) {
          _linked = true;
          _selectedReportId = existeReporte ? reporteInicial : null;
        }
      });
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingReports = false);
      }
    }
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

  Future<void> _useGps() async {
    setState(() => _gettingGps = true);
    try {
      final location =
      await (widget.locationLoader ??
          DeviceLocationService.getCurrentLocation)();
      if (!mounted) return;
      setState(() {
        _selectedLocation = LatLng(location.latitude, location.longitude);
        _locationMethod = 'GPS';
        _locationConfirmed = false;
        _accuracy = location.accuracy;
        _validatedAddress = null;
        _placeId = null;
      });
      await _validateSelectedLocation();
    } catch (error) {
      if (mounted) {
        _showMessage(
          '${error.toString()} Puedes seleccionar el punto manualmente en el mapa.',
        );
      }
    } finally {
      if (mounted) setState(() => _gettingGps = false);
    }
  }

  Future<void> _chooseOnMap() async {
    final initial = _selectedLocation ?? _initialPosition;
    final position = widget.locationPicker == null
        ? await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialPosition: initial,
          selectedPosition: _selectedLocation,
          title: 'Ubicación del avistamiento',
        ),
      ),
    )
        : await widget.locationPicker!(context, initial, _selectedLocation);
    if (!mounted || position == null) return;
    setState(() {
      _selectedLocation = position;
      _locationMethod = 'MAPA';
      _locationConfirmed = false;
      _accuracy = null;
      _validatedAddress = null;
      _placeId = null;
    });
    await _validateSelectedLocation();
  }

  Future<void> _chooseAddress() async {
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
      _locationMethod = 'DIRECCION';
      _locationConfirmed = false;
      _accuracy = null;
      _validatedAddress = selection.formattedAddress;
      _placeId = selection.placeId;
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
      setState(() => _geofenceState = GeofenceValidationState.networkError);
      return false;
    }
  }

  void _changeLocation() {
    setState(() {
      _selectedLocation = null;
      _locationConfirmed = false;
      _locationMethod = null;
      _accuracy = null;
      _validatedAddress = null;
      _placeId = null;
      _geofenceState = GeofenceValidationState.idle;
      _geofenceMode = null;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final selected = await (widget.photoPicker ?? _imagePicker.pickImage)(
      source: source,
    );
    if (!mounted || selected == null) return;
    await _setPhoto(selected);
  }

  Future<void> _setPhoto(XFile selected) async {
    final validation = await validatePetImageSelection(
      selected: [selected],
      alreadyAdded: const [],
      maxImages: 1,
    );
    if (validation.accepted.isEmpty) {
      if (mounted) {
        _showMessage(validation.rejectionMessage ?? 'La foto no es válida.');
      }
      return;
    }
    final bytes = await selected.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photo = selected;
      _photoBytes = bytes;
    });
  }

  Future<void> _showPhotoOptions() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null && mounted) await _pickPhoto(source);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_formGeneration !=
        SessionManager.instance.authenticatedSessionGeneration) {
      _showMessage('La sesión cambió. Abre un nuevo formulario para publicar.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_linked && _selectedReportId == null) {
      _showMessage('Selecciona la mascota perdida que viste.');
      return;
    }
    final location = _selectedLocation;
    if (location == null || _locationMethod == null) {
      _showMessage('Usa tu ubicación o selecciona un punto en el mapa.');
      return;
    }
    if (_photo != null && !_locationConfirmed) {
      _showMessage(
        'Confirma explícitamente la ubicación donde viste la mascota.',
      );
      return;
    }
    if (!geofenceStateAllowsSubmit(_geofenceState)) {
      final allowed = await _validateSelectedLocation();
      if (!allowed || !mounted) return;
    }
    if (_formGeneration !=
        SessionManager.instance.authenticatedSessionGeneration) {
      _showMessage('La sesión cambió. Abre un nuevo formulario para publicar.');
      return;
    }
    setState(() => _saving = true);
    try {
      final SightingCreator create =
          widget.sightingCreator ??
                  ({
                required descripcion,
                reportId,
                required metodo,
                required lat,
                required lng,
                precisionM,
                direccion,
                placeId,
                foto,
              }) => SightingsService.createSighting(
                descripcion: descripcion,
                reportId: reportId,
                metodo: metodo,
                lat: lat,
                lng: lng,
                precisionM: precisionM,
                direccion: direccion,
                placeId: placeId,
                foto: foto,
                solicitudId: foto == null ? null : _requestId,
                ubicacionConfirmada: _locationConfirmed,
                compartirContacto: _shareContact,
              );
      await create(
        descripcion: _descriptionController.text,
        reportId: _linked ? _selectedReportId : null,
        metodo: _locationMethod!,
        lat: location.latitude,
        lng: location.longitude,
        precisionM: _accuracy,
        direccion: _locationMethod == 'DIRECCION' ? _validatedAddress : null,
        placeId: _locationMethod == 'DIRECCION' ? _placeId : null,
        foto: _photo,
      );
      if (!mounted ||
          _formGeneration !=
              SessionManager.instance.authenticatedSessionGeneration) {
        return;
      }
      _submitted = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _photo == null || !_linked
                ? 'Avistamiento registrado correctamente.'
                : 'Avistamiento vinculado registrado correctamente.',
          ),
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _hasUnsavedChanges =>
      !_submitted &&
          (_descriptionController.text.trim().isNotEmpty ||
              _linked ||
              _selectedReportId != null ||
              _selectedLocation != null ||
              _photo != null);

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

  static const _ink = Color(0xFF344955);
  static const _muted = Color(0xFF64786F);
  static const _softGreen = Color(0xFFE6F4EA);

  Widget _sectionCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: const Color(0xFFE1EAE3)),
      boxShadow: const [BoxShadow(color: Color(0x0C203F2F), blurRadius: 12, offset: Offset(0, 4))],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );

  Widget _sectionTitle(IconData icon, String title, {String? subtitle}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: _softGreen, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: _green, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 17)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: _muted, fontSize: 13, height: 1.35)),
                ],
              ],
            )),
          ],
        ),
      );

  Widget _locationButton({required Key key, required IconData icon,
    required String label, required String method, required VoidCallback? onPressed}) {
    final selected = _locationMethod == method;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: _gettingGps && method == 'GPS'
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(selected ? Icons.check_circle : icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? _softGreen : Colors.white,
          foregroundColor: _green,
          side: BorderSide(color: selected ? _green : const Color(0xFFB6D5C1), width: selected ? 1.7 : 1.1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
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
        appBar: AppBar(
          title: const Text('Reportar avistamiento', style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
          backgroundColor: const Color(0xFFDFF3E8),
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
              children: [
                const Text('¿Viste una mascota que podría estar perdida?',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: _ink, height: 1.17)),
                const SizedBox(height: 7),
                const Text('Comparte dónde la viste para ayudar a encontrar a su familia.',
                    style: TextStyle(color: _muted, fontSize: 14, height: 1.4)),
                const SizedBox(height: 22),
                _sectionCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle(Icons.pets_outlined, '¿Reconoces a la mascota?',
                        subtitle: 'Puedes asociar el avistamiento a un reporte existente o publicarlo sin vincular.'),
                    _linkChoices(),
                    if (_linked) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      const Text('Selecciona la mascota reportada',
                          style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                      const SizedBox(height: 9),
                      _linkedReportsSection(),
                    ],
                  ],
                )),
                const SizedBox(height: 16),
                _sectionCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle(Icons.location_on_outlined, 'Última ubicación del avistamiento',
                        subtitle: 'Indica el lugar donde viste a la mascota.'),
                    _locationButton(
                      key: const ValueKey('sighting-use-gps'),
                      icon: Icons.my_location,
                      label: 'Usar mi ubicación actual',
                      method: 'GPS',
                      onPressed: _gettingGps ? null : _useGps,
                    ),
                    const SizedBox(height: 9),
                    _locationButton(
                      key: const ValueKey('sighting-use-map'),
                      icon: Icons.map_outlined,
                      label: 'Elegir ubicación en el mapa',
                      method: 'MAPA',
                      onPressed: _chooseOnMap,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      key: const ValueKey('sighting-location-summary'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedLocation == null ? const Color(0xFFF4F7F5) : _softGreen,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD4E5D9)),
                      ),
                      child: Row(children: [
                        Icon(_selectedLocation == null ? Icons.location_off_outlined : Icons.check_circle_outline,
                            size: 21, color: _green),
                        const SizedBox(width: 9),
                        Expanded(child: Text(
                          _selectedLocation == null
                              ? 'Aún no has seleccionado una ubicación.'
                              : _locationMethod == 'GPS'
                              ? 'Ubicación obtenida. Verifica el punto en el mapa.'
                              : _locationMethod == 'DIRECCION'
                              ? 'Ubicación seleccionada correctamente.'
                              : 'Punto seleccionado en el mapa.',
                          style: const TextStyle(color: _ink, fontSize: 13, height: 1.35),
                        )),
                      ]),
                    ),
                    if (_selectedLocation != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 165,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: widget.miniMapBuilder?.call(context, _selectedLocation!) ??
                              GoogleMap(
                                initialCameraPosition: CameraPosition(target: _selectedLocation!, zoom: 16),
                                liteModeEnabled: true,
                                markers: {Marker(markerId: const MarkerId('sighting-location'), position: _selectedLocation!)},
                                myLocationButtonEnabled: false,
                                mapToolbarEnabled: false,
                              ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GeofenceValidationPanel(
                        state: _geofenceState,
                        onChangeLocation: _changeLocation,
                        onRetry: _validateSelectedLocation,
                      ),
                    ],
                  ],
                )),
                const SizedBox(height: 16),
                _sectionCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle(Icons.edit_note_rounded, 'Descripción del avistamiento',
                        subtitle: 'Cuenta cómo era la mascota y qué observaste.'),
                    TextFormField(
                      key: const ValueKey('sighting-description'),
                      controller: _descriptionController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ej.: perro mediano de color café, visto cerca del parque...',
                        hintStyle: const TextStyle(color: _muted, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFFF9FBF9),
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0xFFD0DED4))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _green, width: 1.5)),
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'La descripción es obligatoria' : null,
                    ),
                  ],
                )),
                const SizedBox(height: 16),
                _sectionCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle(Icons.add_a_photo_outlined, 'Foto del avistamiento',
                        subtitle: 'Opcional. Si tienes una foto, puede ayudar a identificarla.'),
                    if (_photoBytes != null) ...[
                      Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.memory(_photoBytes!,
                              key: const ValueKey('sighting-photo-preview'),
                              height: 190, width: double.infinity, fit: BoxFit.cover),
                        ),
                        Positioned(right: 8, top: 8, child: IconButton.filled(
                          key: const ValueKey('remove-sighting-photo'),
                          onPressed: () => setState(() {
                            _photo = null;
                            _photoBytes = null;
                            _locationConfirmed = false;
                            _shareContact = false;
                          }),
                          icon: const Icon(Icons.close),
                        )),
                      ]),
                      const SizedBox(height: 10),
                    ],
                    OutlinedButton.icon(
                      key: const ValueKey('choose-sighting-photo'),
                      onPressed: _showPhotoOptions,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(_photo == null ? 'Agregar foto' : 'Cambiar foto'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _green,
                        side: const BorderSide(color: _green),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                      ),
                    ),
                    if (_photo != null) ...[
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        key: const ValueKey('sighting-confirm-location'),
                        contentPadding: EdgeInsets.zero,
                        activeColor: _green,
                        value: _locationConfirmed,
                        onChanged: _saving || _selectedLocation == null
                            ? null : (value) => setState(() => _locationConfirmed = value ?? false),
                        title: const Text('Confirmo dónde vi a la mascota',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                        subtitle: const Text('Comprueba que el marcador esté en el lugar correcto.'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        key: const ValueKey('sighting-share-contact'),
                        contentPadding: EdgeInsets.zero,
                        activeColor: _green,
                        value: _shareContact,
                        onChanged: _saving ? null : (value) => setState(() => _shareContact = value ?? false),
                        title: const Text('Compartir mi teléfono si hay coincidencia',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                        subtitle: const Text('Opcional. Tu correo no se comparte.'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ],
                )),
                const SizedBox(height: 22),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    key: const ValueKey('publish-sighting'),
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: _saving
                        ? const SizedBox.square(dimension: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.campaign_outlined),
                    label: Text(_saving ? 'Publicando...' : 'Publicar avistamiento',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: BottomMenuAnimap(
          currentIndex: 1,
          onBeforeNavigate: _confirmDiscard,
          onReportTap: _goToReportSearch,
        ),
      ),
    );
  }

  Widget _linkedReportsSection() {
    if (_loadingReports) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_reports.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'No hay reportes activos disponibles. Puedes registrar el avistamiento como independiente.',
          ),
        ),
      );
    }
    final selected = _reports
        .where((r) => int.tryParse(r['id'].toString()) == _selectedReportId)
        .firstOrNull;
    final petName =
        (selected?['mascota'] as Map?)?['nombre']?.toString() ??
        'Mascota perdida';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected != null)
          Text(
            'Reporte vinculado: $petName',
            key: const ValueKey('sighting-linked-report-summary'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        if (selected == null && widget.reporteInicialId != null)
          const Text(
            'El reporte seleccionado ya no está disponible. Elige otro reporte o vuelve a la búsqueda.',
          ),
        ..._reports.map(_reportOption),
      ],
    );
  }

  Widget _linkChoices() {
    final linked = _linkChoice(
      key: const ValueKey('linked-sighting'),
      selected: _linked,
      icon: Icons.search_rounded,
      label: 'Vincular a un reporte',
      description: 'La mascota aparece entre las reportadas como perdidas.',
      onTap: () => setState(() => _linked = true),
    );
    final independent = _linkChoice(
      key: const ValueKey('independent-sighting'),
      selected: !_linked,
      icon: Icons.add_location_alt_outlined,
      label: 'Reportar sin vincular',
      description: 'No encontré a la mascota entre los reportes.',
      onTap: () => setState(() {
        _linked = false;
        _selectedReportId = null;
      }),
    );
    return Column(children: [linked, const SizedBox(height: 9), independent]);
  }

  Widget _linkChoice({
    required Key key,
    required bool selected,
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? _softGreen : const Color(0xFFFAFCFA),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: selected ? _green : const Color(0xFFDDE8DF), width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(children: [
            Icon(icon, color: _green, size: 24),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Text(description, style: const TextStyle(color: _muted, fontSize: 12, height: 1.3)),
            ])),
            const SizedBox(width: 8),
            Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: _green),
          ]),
        ),
      ),
    );
  }

  Widget _reportOption(Map<String, dynamic> report) {
    final id = int.tryParse(report['id']?.toString() ?? '');
    final pet = report['mascota'] is Map
        ? Map<String, dynamic>.from(report['mascota'] as Map)
        : <String, dynamic>{};
    final photo = pet['fotoPrincipal'] is Map
        ? Map<String, dynamic>.from(pet['fotoPrincipal'] as Map)
        : null;
    final imageUrl = SightingsService.absoluteImageUrl(photo?['url']);
    final selected = id != null && id == _selectedReportId;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: selected ? _softGreen : const Color(0xFFFAFCFA),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: selected ? _green : const Color(0xFFDDE8DF), width: selected ? 1.6 : 1)),
      child: InkWell(
        key: ValueKey('linkable-report-$id'),
        onTap: id == null ? null : () => setState(() => _selectedReportId = id),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl == null
                    ? const SizedBox.square(
                  dimension: 54,
                  child: ColoredBox(
                    color: Color(0xFFE5F1E8),
                    child: Icon(Icons.pets, color: _green),
                  ),
                )
                    : Image.network(
                  imageUrl,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.square(
                    dimension: 54,
                    child: ColoredBox(
                      color: Color(0xFFE5F1E8),
                      child: Icon(Icons.pets),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet['nombre']?.toString() ?? 'Mascota',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      [pet['especie'], pet['raza']]
                          .where(
                            (value) =>
                        value != null && value.toString().isNotEmpty,
                      )
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: _green,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
