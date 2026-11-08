import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/image_recognition_service.dart';

class ImageSearchSheet extends StatefulWidget {
  const ImageSearchSheet({
    super.key,
    required this.initialImage,
    required this.pickImage,
    this.search,
  });
  final XFile initialImage;
  final Future<XFile?> Function(ImageSource) pickImage;
  final Future<RecognitionResults> Function(XFile)? search;
  @override
  State<ImageSearchSheet> createState() => _ImageSearchSheetState();
}

class _ImageSearchSheetState extends State<ImageSearchSheet> {
  static const green = Color(0xFF21986A);
  late final ImageRecognitionService _service;
  XFile? _photo;
  Uint8List? _preview;
  RecognitionResults? _results;
  String? _error;
  bool _busy = false, _picking = false;
  int _selection = 0;
  @override
  void initState() {
    super.initState();
    _service = ImageRecognitionService();
    _prepare(widget.initialImage);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _prepare(XFile photo) async {
    final selection = ++_selection;
    setState(() {
      _preview = null;
      _photo = null;
      _results = null;
      _error = null;
    });
    try {
      if (await photo.length() > 5 * 1024 * 1024) {
        throw const RecognitionException(
          'La fotografía debe pesar máximo 5 MiB.',
        );
      }
      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        throw const RecognitionException(
          'La fotografía está vacía o supera 5 MiB.',
        );
      }
      if (mounted && selection == _selection) {
        setState(() {
          _photo = photo;
          _preview = bytes;
        });
      }
    } catch (_) {
      if (mounted && selection == _selection) {
        setState(() {
          _error =
              'No se pudo cargar la fotografía. Usa una imagen de máximo 5 MiB.';
        });
      }
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy || _picking) return;
    setState(() {
      _picking = true;
    });
    try {
      final image = await widget.pickImage(source);
      if (mounted && image != null) await _prepare(image);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No fue posible seleccionar la imagen.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
        });
      }
    }
  }

  Future<void> _search() async {
    if (_busy || _photo == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _results = null;
    });
    try {
      final results = await (widget.search ?? _service.search)(_photo!);
      if (mounted) {
        setState(() {
          _results = results;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is RecognitionException
              ? error.message
              : 'No fue posible realizar la búsqueda. Intenta nuevamente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
    children: [
      const Text(
        'Buscar mascota por imagen',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Posibles coincidencias. La similitud visual no confirma que sea la misma mascota.',
      ),
      const SizedBox(height: 16),
      if (_preview != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            _preview!,
            height: 180,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 120,
              child: Center(child: Text('No se pudo mostrar la imagen')),
            ),
          ),
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: _busy || _picking
                ? null
                : () => _pick(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Tomar otra fotografía'),
          ),
          TextButton.icon(
            onPressed: _busy || _picking
                ? null
                : () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Elegir otra imagen'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _busy || _picking || _photo == null ? null : _search,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          minimumSize: const Size(0, 48),
        ),
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.search),
        label: Text(_busy ? 'Buscando coincidencias…' : 'Buscar coincidencias'),
      ),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!)),
      if (_results case final results?) ...[
        const SizedBox(height: 20),
        if (results.matches.isEmpty)
          const Text('No se encontraron mascotas similares'),
        if (results.skippedImages > 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Algunas fotografías registradas no estuvieron disponibles para comparar.',
            ),
          ),
        for (final match in results.matches)
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.pop(context, match.reportId),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 72,
                      child: Image.network(
                        match.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.pets, color: green),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            match.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(match.species),
                          Text(
                            'Similitud visual: ${(match.similarity * 100).toStringAsFixed(1)} %',
                          ),
                          const Text(
                            'Ver reporte',
                            style: TextStyle(color: green),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: green),
                  ],
                ),
              ),
            ),
          ),
      ],
    ],
  );
}
