import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../features/report/data/geocoding_service.dart';
import '../features/report/data/geofence_service.dart';

typedef AddressGeocoder = Future<GeocodingResult> Function(String address);
typedef AddressMiniMapBuilder =
    Widget Function(BuildContext context, LatLng position);

class AddressLocationPage extends StatefulWidget {
  const AddressLocationPage({
    super.key,
    this.initialAddress,
    this.initialSelection,
    this.geocoder,
    this.miniMapBuilder,
  });

  final String? initialAddress;
  final AddressLocationSelection? initialSelection;
  final AddressGeocoder? geocoder;
  final AddressMiniMapBuilder? miniMapBuilder;

  @override
  State<AddressLocationPage> createState() => _AddressLocationPageState();
}

class _AddressLocationPageState extends State<AddressLocationPage> {
  static const _green = Color(0xFF3F9568);
  final _controller = TextEditingController();
  bool _loading = false;
  List<GeocodingCandidate> _candidates = const [];
  GeocodingCandidate? _selected;
  String? _mode;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSelection;
    _controller.text = initial?.formattedAddress ?? widget.initialAddress ?? '';
    if (initial != null) {
      final candidate = GeocodingCandidate(
        formattedAddress: initial.formattedAddress,
        lat: initial.lat,
        lng: initial.lng,
        placeId: initial.placeId,
        locationType: 'VALIDATED',
        inside: initial.inside,
        allowed: initial.allowed,
      );
      _candidates = [candidate];
      _selected = candidate;
      _mode = initial.mode;
    }
    _controller.addListener(_invalidateValidatedAddress);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_invalidateValidatedAddress)
      ..dispose();
    super.dispose();
  }

  void _invalidateValidatedAddress() {
    if (_candidates.isEmpty && _selected == null && _error == null) return;
    setState(() {
      _candidates = const [];
      _selected = null;
      _mode = null;
      _error = null;
    });
  }

  Future<void> _validate() async {
    final address = _controller.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'La dirección es obligatoria.');
      return;
    }
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await (widget.geocoder ?? GeocodingService.geocode)(
        address,
      );
      if (!mounted) return;
      setState(() {
        _mode = result.mode;
        _candidates = result.candidates;
        _selected = result.candidates.length == 1
            ? result.candidates.first
            : null;
        if (result.candidates.isEmpty) {
          _error =
              'No encontramos esa dirección. Verifica los datos e inténtalo nuevamente.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirm() {
    final candidate = _selected;
    final mode = _mode;
    if (candidate == null || mode == null || !candidate.allowed) return;
    Navigator.pop(
      context,
      AddressLocationSelection(
        formattedAddress: candidate.formattedAddress,
        lat: candidate.lat,
        lng: candidate.lng,
        placeId: candidate.placeId,
        inside: candidate.inside,
        allowed: candidate.allowed,
        mode: mode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Ingresar dirección')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey('manual-address-input'),
              controller: _controller,
              maxLength: 300,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                hintText: 'Ej. Carrera 68B # 24-39',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _validate(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('validate-manual-address'),
              onPressed: _loading ? null : _validate,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: const Text('Validar dirección'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('manual-address-error'),
                style: const TextStyle(color: Color(0xFFD1493F)),
              ),
            ],
            if (_candidates.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                _candidates.length == 1
                    ? 'Dirección encontrada'
                    : 'Selecciona una dirección',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ..._candidates.map(
                (candidate) => Card(
                  child: ListTile(
                    key: ValueKey('address-candidate-${candidate.placeId}'),
                    onTap: () => setState(() => _selected = candidate),
                    leading: Icon(
                      identical(candidate, selected)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _green,
                    ),
                    title: Text(candidate.formattedAddress),
                    subtitle: Text(
                      candidate.inside
                          ? 'Dentro de Salitre Occidental'
                          : candidate.allowed
                          ? 'Fuera de la zona · modo de pruebas'
                          : 'Fuera de la zona permitida',
                    ),
                  ),
                ),
              ),
            ],
            if (selected != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child:
                      widget.miniMapBuilder?.call(
                        context,
                        LatLng(selected.lat, selected.lng),
                      ) ??
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(selected.lat, selected.lng),
                          zoom: 16,
                        ),
                        liteModeEnabled: true,
                        markers: {
                          Marker(
                            markerId: const MarkerId('geocoded-address'),
                            position: LatLng(selected.lat, selected.lng),
                          ),
                        },
                        myLocationButtonEnabled: false,
                        mapToolbarEnabled: false,
                      ),
                ),
              ),
              const SizedBox(height: 10),
              if (!selected.inside)
                Container(
                  key: const ValueKey('address-zone-message'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected.allowed
                        ? const Color(0xFFFFF5D9)
                        : const Color(0xFFFFE8E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    selected.allowed
                        ? outsideAllowedAreaWarningMessage.replaceFirst(
                            'ubicación',
                            'dirección',
                          )
                        : outsideAllowedAreaMessage.replaceFirst(
                            'ubicación',
                            'dirección',
                          ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('use-manual-address'),
                onPressed: selected.allowed ? _confirm : null,
                style: FilledButton.styleFrom(backgroundColor: _green),
                child: const Text('Usar esta dirección'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
