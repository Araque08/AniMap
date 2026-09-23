import 'dart:typed_data';

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
    this.reportsLoader,
    this.sightingCreator,
    this.locationLoader,
    this.photoPicker,
    this.miniMapBuilder,
    this.locationPicker,
    this.geofenceChecker,
    this.addressPicker,
  });

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
  bool _gettingGps = false;
  bool _saving = false;
  bool _submitted = false;
  bool _allowPop = false;
  GeofenceValidationState _geofenceState = GeofenceValidationState.idle;
  String? _geofenceMode;

  @override
  void initState() {
    super.initState();
    _loadReports();
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
      if (mounted) setState(() => _reports = reports);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _loadingReports = false);
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
    if (selected == null) return;
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
    if (!geofenceStateAllowsSubmit(_geofenceState)) {
      final allowed = await _validateSelectedLocation();
      if (!allowed) return;
    }
    setState(() => _saving = true);
    try {
      final create = widget.sightingCreator ?? SightingsService.createSighting;
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
      if (!mounted) return;
      _submitted = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avistamiento registrado correctamente.')),
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
        backgroundColor: const Color(0xFFF4F8F5),
        appBar: AppBar(
          title: const Text('Reportar avistamiento'),
          backgroundColor: const Color(0xFFDFF3E8),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
              children: [
                const Text(
                  '¿Quieres vincular este avistamiento a una mascota perdida?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                _linkChoices(),
                if (_linked) _linkedReportsSection(),
                const SizedBox(height: 10),
                const Text(
                  'Ubicación',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  color: Colors.white,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('sighting-use-gps'),
                        onPressed: _gettingGps ? null : _useGps,
                        icon: _gettingGps
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('Usar mi ubicación'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('sighting-use-map'),
                        onPressed: _chooseOnMap,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Seleccionar en el mapa'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('sighting-use-address'),
                        onPressed: _chooseAddress,
                        icon: const Icon(Icons.edit_location_alt_outlined),
                        label: const Text('Ingresar dirección'),
                      ),
                    ],
                  ),
                ),
                if (_selectedLocation != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 145,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child:
                          widget.miniMapBuilder?.call(
                            context,
                            _selectedLocation!,
                          ) ??
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _selectedLocation!,
                              zoom: 16,
                            ),
                            liteModeEnabled: true,
                            markers: {
                              Marker(
                                markerId: const MarkerId('sighting-location'),
                                position: _selectedLocation!,
                              ),
                            },
                            myLocationButtonEnabled: false,
                            mapToolbarEnabled: false,
                          ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _locationMethod == 'DIRECCION'
                        ? _validatedAddress ?? 'Dirección validada'
                        : '$_locationMethod · ${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                              '${_selectedLocation!.longitude.toStringAsFixed(6)}',
                    key: const ValueKey('sighting-location-summary'),
                    style: const TextStyle(color: Color(0xFF65756C)),
                  ),
                  const SizedBox(height: 9),
                  GeofenceValidationPanel(
                    state: _geofenceState,
                    onChangeLocation: _changeLocation,
                    onRetry: _validateSelectedLocation,
                  ),
                ],
                const SizedBox(height: 18),
                TextFormField(
                  key: const ValueKey('sighting-description'),
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Descripción breve',
                    hintText: 'Describe la mascota y lo que observaste.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'La descripción es obligatoria'
                      : null,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Foto opcional',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (_photoBytes != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          _photoBytes!,
                          key: const ValueKey('sighting-photo-preview'),
                          height: 190,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: IconButton.filled(
                          key: const ValueKey('remove-sighting-photo'),
                          onPressed: () => setState(() {
                            _photo = null;
                            _photoBytes = null;
                          }),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('choose-sighting-photo'),
                  onPressed: _showPhotoOptions,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    _photo == null ? 'Agregar foto' : 'Reemplazar foto',
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const ValueKey('publish-sighting'),
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Publicar avistamiento'),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: BottomMenuAnimap(
          currentIndex: 1,
          onBeforeNavigate: _confirmDiscard,
          onReportTap: _goToReportSelector,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [..._reports.map(_reportOption)],
    );
  }

  Widget _linkChoices() {
    final linked = _linkChoice(
      key: const ValueKey('linked-sighting'),
      selected: _linked,
      label: 'Seleccionar mascota reportada',
      description:
          'Busca entre las mascotas que actualmente están reportadas como perdidas.',
      onTap: () => setState(() => _linked = true),
    );
    final independent = _linkChoice(
      key: const ValueKey('independent-sighting'),
      selected: !_linked,
      label: 'Reportar sin vincular',
      description:
          'Usa esta opción si no identificas la mascota entre los reportes actuales.',
      onTap: () => setState(() {
        _linked = false;
        _selectedReportId = null;
      }),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280) {
          return Column(children: [linked, independent]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: linked),
            const SizedBox(width: 8),
            Expanded(child: independent),
          ],
        );
      },
    );
  }

  Widget _linkChoice({
    required Key key,
    required bool selected,
    required String label,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: selected ? const Color(0xFFDFF3E8) : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: _green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF65756C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: selected ? const Color(0xFFDFF3E8) : Colors.white,
      child: InkWell(
        key: ValueKey('linkable-report-$id'),
        onTap: id == null ? null : () => setState(() => _selectedReportId = id),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl == null
                    ? const SizedBox.square(
                        dimension: 42,
                        child: ColoredBox(
                          color: Color(0xFFE5F1E8),
                          child: Icon(Icons.pets, color: _green),
                        ),
                      )
                    : Image.network(
                        imageUrl,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.square(
                          dimension: 42,
                          child: ColoredBox(
                            color: Color(0xFFE5F1E8),
                            child: Icon(Icons.pets),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
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
