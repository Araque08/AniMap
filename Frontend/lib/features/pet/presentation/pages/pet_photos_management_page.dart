import 'package:flutter/material.dart';

import '../../data/mascotas_service.dart';
import '../../data/pet_image_selection.dart';

class PetPhotosManagementPage extends StatefulWidget {
  final int mascotaId;

  const PetPhotosManagementPage({super.key, required this.mascotaId});

  @override
  State<PetPhotosManagementPage> createState() =>
      _PetPhotosManagementPageState();
}

class _PetPhotosManagementPageState extends State<PetPhotosManagementPage> {
  static const _green = Color(0xFF3F9568);
  static const _minimumPhotos = 15;

  List<Map<String, dynamic>> _photos = const [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    if (mounted) setState(() => _loading = true);
    try {
      final photos = await MascotasService.obtenerImagenesMascota(
        mascotaId: widget.mascotaId,
      );
      if (!mounted) return;
      setState(() {
        _photos = principalImageFirst(
          photos,
          (photo) => photo['esPrincipal'] == true,
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(error.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _setPrincipal(Map<String, dynamic> photo) async {
    if (photo['esPrincipal'] == true) return;
    try {
      await MascotasService.establecerFotoPrincipal(
        mascotaId: widget.mascotaId,
        imageId: photo['id'].toString(),
      );
      _changed = true;
      await _loadPhotos();
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    if (!canDeletePetImage(_photos.length, minimum: _minimumPhotos)) {
      _showMessage('No puedes dejar la mascota con menos de 15 fotos.');
      return;
    }
    try {
      await MascotasService.eliminarFoto(
        mascotaId: widget.mascotaId,
        imageId: photo['id'].toString(),
      );
      _changed = true;
      await _loadPhotos();
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  void _movePhoto(int from, int to) {
    if (from <= 0 || from >= _photos.length || to <= 0) return;
    setState(() {
      final reordered = List<Map<String, dynamic>>.from(_photos);
      moveSecondaryImage(reordered, from, to);
      _photos = reordered;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar fotos'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.pop(context, _changed),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(
                    '${_photos.length} fotos · mínimo requerido: 15\n'
                    'Mantén pulsada una foto secundaria y arrástrala para reorganizarla visualmente.',
                    style: const TextStyle(color: Color(0xFF5D6F65)),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    key: const ValueKey('pet-photos-grid'),
                    padding: const EdgeInsets.all(10),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 0.78,
                        ),
                    itemCount: _photos.length,
                    itemBuilder: (context, index) {
                      final photo = _photos[index];
                      return _photoDropTarget(photo, index);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _photoDropTarget(Map<String, dynamic> photo, int index) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) =>
          details.data > 0 && index > 0 && details.data != index,
      onAcceptWithDetails: (details) => _movePhoto(details.data, index),
      builder: (context, candidates, rejected) {
        final tile = _photoTile(photo, index, candidates.isNotEmpty);
        if (index == 0) return tile;
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 88, height: 110, child: tile),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: tile,
        );
      },
    );
  }

  Widget _photoTile(Map<String, dynamic> photo, int index, bool highlighted) {
    final isPrincipal = photo['esPrincipal'] == true;
    final imageUrl = '${MascotasService.originUrl}${photo['url']}';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted || isPrincipal ? _green : const Color(0xFFD1D5DB),
          width: isPrincipal ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imageUrl,
              headers: MascotasService.authHeaders,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: Color(0xFFE5E7EB),
                child: Icon(Icons.pets),
              ),
            ),
            Positioned(
              left: 3,
              bottom: 3,
              child: Material(
                color: isPrincipal ? _green : Colors.black54,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: isPrincipal ? null : () => _setPrincipal(photo),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      isPrincipal ? Icons.star : Icons.star_border,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 3,
              top: 3,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _deletePhoto(photo),
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            if (isPrincipal)
              const Positioned(
                left: 4,
                right: 4,
                top: 4,
                child: Text(
                  'Principal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
