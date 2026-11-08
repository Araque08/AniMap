import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/mascotas_service.dart';
import '../../data/pet_image_selection.dart';

typedef PetPhotosLoader =
    Future<List<Map<String, dynamic>>> Function({required int mascotaId});
typedef PetPhotoBytesLoader = Future<List<int>> Function(String url);
typedef PetPhotosPicker = Future<List<XFile>> Function();
typedef PetPhotosBatchSaver =
    Future<void> Function({
      required int mascotaId,
      required List<String> originalImageIds,
      required List<String> retainedImageIds,
      required List<XFile> newImages,
      String? principalExistingId,
      int? principalNewIndex,
    });

class PetPhotosManagementPage extends StatefulWidget {
  final int mascotaId;
  final PetPhotosLoader? photosLoader;
  final PetPhotoBytesLoader? photoBytesLoader;
  final PetPhotosPicker? photosPicker;
  final PetPhotosBatchSaver? batchSaver;

  const PetPhotosManagementPage({
    super.key,
    required this.mascotaId,
    this.photosLoader,
    this.photoBytesLoader,
    this.photosPicker,
    this.batchSaver,
  });

  @override
  State<PetPhotosManagementPage> createState() =>
      _PetPhotosManagementPageState();
}

class _EditablePetPhoto {
  _EditablePetPhoto.existing(Map<String, dynamic> existing)
    : source = existing,
      file = null,
      bytes = null,
      isPrincipal = existing['esPrincipal'] == true;

  _EditablePetPhoto.newImage(this.file, this.bytes)
    : source = null,
      isPrincipal = false;

  final Map<String, dynamic>? source;
  final XFile? file;
  Uint8List? bytes;
  bool isPrincipal;
  bool unavailable = false;

  bool get isExisting => source != null;
  String? get id => source?['id']?.toString();
  String? get url => source?['url']?.toString();
  String get localKey => id ?? 'new-${file!.name}';
}

class _PetPhotosManagementPageState extends State<PetPhotosManagementPage> {
  static const _green = Color(0xFF3F9568);
  static const _minimumPhotos = 15;

  final List<_EditablePetPhoto> _removedOriginals = [];
  final Map<String, Uint8List> _remoteBytes = {};
  List<_EditablePetPhoto> _photos = [];
  bool _loading = true;
  bool _saving = false;
  bool _checkingPhotos = false;
  bool _comparisonFailed = false;
  bool _hasPendingChanges = false;
  bool _savedAnyChanges = false;
  bool _allowPop = false;

  bool get _busy => _saving || _checkingPhotos;
  int get _validPhotoCount =>
      _photos.where((photo) => !photo.unavailable).length;
  bool get _hasUnavailablePhotos => _photos.any((photo) => photo.unavailable);

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    if (mounted) setState(() => _loading = true);
    try {
      final photos =
          await (widget.photosLoader ?? MascotasService.obtenerImagenesMascota)(
            mascotaId: widget.mascotaId,
          );
      if (!mounted) return;
      final ordered = principalImageFirst(
        photos,
        (photo) => photo['esPrincipal'] == true,
      );
      setState(() {
        _photos = ordered.map(_EditablePetPhoto.existing).toList();
        _removedOriginals.clear();
        _remoteBytes.clear();
        _hasPendingChanges = false;
        _comparisonFailed = false;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(_cleanError(error));
    }
  }

  Future<void> _pickPhotos() async {
    if (_busy || _loading) return;
    setState(() => _checkingPhotos = true);
    try {
      final picked =
          await (widget.photosPicker ?? () => ImagePicker().pickMultiImage())();
      if (picked.isEmpty || !mounted) return;
      final validation = await validatePetImageSelection(
        selected: picked,
        alreadyAdded: _photos
            .where((photo) => !photo.isExisting)
            .map((photo) => photo.file!)
            .toList(),
      );
      if (!mounted) return;
      var activeDuplicates = 0;
      final restorations = <_EditablePetPhoto>[];
      final additions = <_EditablePetPhoto>[];
      // Validate every original, even if a duplicate is found early in the list.
      if (validation.accepted.isNotEmpty) {
        for (final photo in [..._photos, ..._removedOriginals]) {
          if (!photo.isExisting || photo.unavailable) continue;
          try {
            await _bytesFor(photo);
          } on PetPhotoReadException catch (error) {
            if (!error.unavailable) rethrow;
            photo.unavailable = true;
          }
          if (!mounted) return;
        }
      }
      for (final file in validation.accepted) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        final removedMatch = await _findSameContent(_removedOriginals, bytes);
        if (!mounted) return;
        if (removedMatch != null) {
          restorations.add(removedMatch);
          additions.add(removedMatch);
          continue;
        }
        if (await _findSameContent(_photos, bytes) != null ||
            await _findSameContent(additions, bytes) != null) {
          activeDuplicates += 1;
          continue;
        }
        if (!mounted) return;
        additions.add(_EditablePetPhoto.newImage(file, bytes));
      }
      if (!mounted) return;
      // Aplicar la selección únicamente cuando terminaron todas las comparaciones.
      setState(() {
        if (validation.accepted.isNotEmpty) _comparisonFailed = false;
        if (additions.isNotEmpty) {
          _removedOriginals.removeWhere(restorations.contains);
          _photos.addAll(additions);
          if (!_photos.any((photo) => photo.isPrincipal)) {
            _photos.first.isPrincipal = true;
          }
          _movePrincipalFirst();
          _hasPendingChanges = true;
        }
      });
      final messages = <String>[
        if (validation.rejectionMessage != null) validation.rejectionMessage!,
        if (activeDuplicates == 1) 'Esta foto ya fue agregada.',
        if (activeDuplicates > 1)
          '$activeDuplicates fotos ya fueron agregadas.',
        if (_hasUnavailablePhotos)
          'Una foto existente ya no está disponible. Recarga la galería o retírala y agrega un reemplazo antes de guardar.',
        if (restorations.isNotEmpty)
          restorations.length == 1
              ? 'Se restauró la foto original sin volver a subirla.'
              : 'Se restauraron ${restorations.length} fotos originales sin volver a subirlas.',
      ];
      if (messages.isNotEmpty) _showMessage(messages.join(' '));
    } catch (error) {
      if (!mounted) return;
      setState(() => _comparisonFailed = true);
      final reason = error is PetPhotoReadException
          ? error.message
          : 'No pudimos leer o comparar una foto. Inténtalo nuevamente.';
      _showMessage(
        '$reason No se guardaron cambios. Vuelve a agregar las fotos para reintentar.',
      );
    } finally {
      if (mounted) setState(() => _checkingPhotos = false);
    }
  }

  Future<_EditablePetPhoto?> _findSameContent(
    Iterable<_EditablePetPhoto> candidates,
    Uint8List selected,
  ) async {
    for (final candidate in candidates) {
      if (candidate.unavailable) continue;
      final bytes = await _bytesFor(candidate);
      if (!mounted) return null;
      if (_sameBytes(bytes, selected)) return candidate;
    }
    return null;
  }

  Future<Uint8List> _bytesFor(_EditablePetPhoto photo) async {
    if (photo.bytes != null) return photo.bytes!;
    final id = photo.id;
    final url = photo.url;
    if (id == null || url == null) {
      throw const PetPhotoReadException(
        'Una foto no tiene una referencia válida. Recarga la galería.',
      );
    }
    final cached = _remoteBytes[id];
    if (cached != null) return cached;
    final loaded = Uint8List.fromList(
      await (widget.photoBytesLoader ?? MascotasService.descargarFoto)(url),
    );
    _remoteBytes[id] = loaded;
    photo.bytes = loaded;
    return loaded;
  }

  void _setPrincipal(_EditablePetPhoto photo) {
    if (_busy || photo.isPrincipal || photo.unavailable) return;
    setState(() {
      for (final item in _photos) {
        item.isPrincipal = identical(item, photo);
      }
      _movePrincipalFirst();
      _hasPendingChanges = true;
    });
  }

  void _deletePhoto(_EditablePetPhoto photo) {
    if (_busy) return;
    setState(() {
      final wasPrincipal = photo.isPrincipal;
      _photos.remove(photo);
      if (wasPrincipal) photo.isPrincipal = false;
      if (photo.isExisting) _removedOriginals.add(photo);
      if (wasPrincipal && _photos.isNotEmpty) {
        for (final item in _photos) {
          item.isPrincipal = false;
        }
        final available = _photos.where((item) => !item.unavailable);
        if (available.isNotEmpty) available.first.isPrincipal = true;
      }
      _movePrincipalFirst();
      _hasPendingChanges = true;
    });
  }

  void _movePhoto(int from, int to) {
    if (_busy) return;
    if (from <= 0 || from >= _photos.length || to <= 0) return;
    setState(() {
      moveSecondaryImage(_photos, from, to);
      _hasPendingChanges = true;
    });
  }

  void _movePrincipalFirst() {
    final principal = _photos.indexWhere((photo) => photo.isPrincipal);
    if (principal > 0) moveImageToFirst(_photos, principal);
  }

  Future<void> _saveChanges() async {
    if (_busy || _loading) return;
    if (_comparisonFailed) {
      _showMessage(
        'No se guardaron cambios. Vuelve a agregar las fotos para completar la validación.',
      );
      return;
    }
    if (_validPhotoCount < _minimumPhotos) {
      _showMessage(
        'Debes mantener mínimo 15 fotografías. Actualmente tienes $_validPhotoCount.',
      );
      return;
    }
    if (_hasUnavailablePhotos) {
      _showMessage(
        'Hay fotos no disponibles. Recarga la galería o retíralas y agrega reemplazos antes de guardar.',
      );
      return;
    }
    final principals = _photos.where((photo) => photo.isPrincipal).toList();
    if (principals.length != 1) {
      _showMessage('Debes seleccionar exactamente una foto principal.');
      return;
    }
    if (!_hasPendingChanges) {
      _showMessage('No hay cambios por guardar.');
      return;
    }

    final retained = _photos.where((photo) => photo.isExisting).toList();
    final newPhotos = _photos.where((photo) => !photo.isExisting).toList();
    final principal = principals.single;
    setState(() => _saving = true);
    try {
      await (widget.batchSaver ?? MascotasService.guardarCambiosFotos)(
        mascotaId: widget.mascotaId,
        originalImageIds: [
          ...retained.map((photo) => photo.id!),
          ..._removedOriginals.map((photo) => photo.id!),
        ],
        retainedImageIds: retained.map((photo) => photo.id!).toList(),
        newImages: newPhotos.map((photo) => photo.file!).toList(),
        principalExistingId: principal.isExisting ? principal.id : null,
        principalNewIndex: principal.isExisting
            ? null
            : newPhotos.indexOf(principal),
      );
      _savedAnyChanges = true;
      await _loadPhotos();
      if (mounted) _showMessage('Fotos actualizadas correctamente.');
    } catch (error) {
      if (mounted) _showMessage(_cleanError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmExit() async {
    if (!_hasPendingChanges) return true;
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

  Future<void> _leave() async {
    if (_busy) return;
    if (await _confirmExit() && mounted) {
      setState(() => _allowPop = true);
      Navigator.pop(context, _savedAnyChanges);
    }
  }

  Future<void> _reloadGallery() async {
    if (_busy || _loading) return;
    if (await _confirmExit() && mounted) await _loadPhotos();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestionar fotos'),
          backgroundColor: _green,
          foregroundColor: Colors.white,
          leading: IconButton(
            onPressed: _busy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: 'Recargar galería',
              onPressed: _busy || _loading ? null : _reloadGallery,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text(
                      '${_hasUnavailablePhotos ? '$_validPhotoCount fotos válidas · ${_photos.length - _validPhotoCount} no disponibles' : '${_photos.length} fotos · mínimo requerido: 15'}\n'
                      'Los cambios se aplican únicamente al pulsar Guardar cambios.',
                      style: const TextStyle(color: Color(0xFF5D6F65)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      key: const ValueKey('add-managed-photos'),
                      onPressed: _busy ? null : _pickPhotos,
                      icon: _checkingPhotos
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Agregar fotos'),
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
                      itemBuilder: (context, index) =>
                          _photoDropTarget(_photos[index], index),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: FilledButton.icon(
                      key: const ValueKey('save-photo-changes'),
                      onPressed: _busy ? null : _saveChanges,
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Guardar cambios'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _photoDropTarget(_EditablePetPhoto photo, int index) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) =>
          !_busy && details.data > 0 && index > 0 && details.data != index,
      onAcceptWithDetails: (details) => _movePhoto(details.data, index),
      builder: (context, candidates, rejected) {
        final tile = _photoTile(photo, candidates.isNotEmpty);
        if (index == 0) return tile;
        return LongPressDraggable<int>(
          data: index,
          maxSimultaneousDrags: _busy ? 0 : 1,
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

  Widget _photoTile(_EditablePetPhoto photo, bool highlighted) {
    final image = photo.isExisting
        ? Image.network(
            MascotasService.absoluteImageUrl(photo.url ?? ''),
            headers: MascotasService.authHeaders,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0xFFE5E7EB),
              child: Icon(Icons.pets),
            ),
          )
        : Image.memory(photo.bytes!, fit: BoxFit.cover);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted || photo.isPrincipal
              ? _green
              : const Color(0xFFD1D5DB),
          width: photo.isPrincipal ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            Positioned(
              left: 3,
              bottom: 3,
              child: Material(
                color: photo.isPrincipal ? _green : Colors.black54,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey('principal-photo-${photo.localKey}'),
                  onTap: _busy || photo.isPrincipal || photo.unavailable
                      ? null
                      : () => _setPrincipal(photo),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      photo.isPrincipal ? Icons.star : Icons.star_border,
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
                  key: ValueKey('delete-photo-${photo.localKey}'),
                  onTap: _busy ? null : () => _deletePhoto(photo),
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
            if (photo.isPrincipal)
              const Positioned(
                left: 4,
                right: 4,
                top: 4,
                child: IgnorePointer(
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
              ),
            if (photo.unavailable)
              const Center(
                child: ColoredBox(
                  color: Color(0xFFE5E7EB),
                  child: Text(
                    'No disponible',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Color(0xFF374151)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
