import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

typedef LocationMapBuilder =
    Widget Function(
      BuildContext context,
      LatLng initialPosition,
      LatLng? selectedPosition,
      ValueChanged<LatLng> onSelect,
    );

class LocationPickerPage extends StatefulWidget {
  final LatLng initialPosition;
  final LatLng? selectedPosition;
  final String title;
  final LocationMapBuilder? mapBuilder;

  const LocationPickerPage({
    super.key,
    required this.initialPosition,
    this.selectedPosition,
    this.title = 'Elegir ubicación',
    this.mapBuilder,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  static const _green = Color(0xFF3F9568);
  LatLng? _selectedPosition;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.selectedPosition;
  }

  void _selectPosition(LatLng position) {
    setState(() => _selectedPosition = position);
  }

  void _confirm() {
    final position = _selectedPosition;
    if (position != null) Navigator.pop(context, position);
  }

  @override
  Widget build(BuildContext context) {
    final target = _selectedPosition ?? widget.initialPosition;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child:
                widget.mapBuilder?.call(
                  context,
                  target,
                  _selectedPosition,
                  _selectPosition,
                ) ??
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: target,
                    zoom: 15,
                  ),
                  onTap: _selectPosition,
                  markers: _selectedPosition == null
                      ? const {}
                      : {
                          Marker(
                            markerId: const MarkerId('selected-location'),
                            position: _selectedPosition!,
                          ),
                        },
                  compassEnabled: true,
                  mapToolbarEnabled: false,
                  myLocationButtonEnabled: false,
                  rotateGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  zoomControlsEnabled: true,
                  zoomGesturesEnabled: true,
                ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: Colors.white,
                elevation: 3,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    'Toca el mapa para colocar o mover el marcador.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: FilledButton.icon(
                key: const ValueKey('confirm-location'),
                onPressed: _selectedPosition == null ? null : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirmar ubicación'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
