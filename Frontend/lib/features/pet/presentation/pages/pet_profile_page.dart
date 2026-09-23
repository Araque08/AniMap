import 'package:flutter/material.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../../map/presentation/pages/map_page.dart';
import '../../data/mascotas_service.dart';
import 'register_pet_page.dart';

typedef PetProfileLoader = Future<PetProfile> Function(int mascotaId);
typedef PetDeleteAction = Future<void> Function(int mascotaId);

class PetProfilePage extends StatefulWidget {
  final int mascotaId;
  final bool mostrarAccionesDueno;
  final PetProfileLoader? profileLoader;
  final PetDeleteAction? deleteAction;

  const PetProfilePage({
    super.key,
    required this.mascotaId,
    this.mostrarAccionesDueno = true,
    this.profileLoader,
    this.deleteAction,
  });

  @override
  State<PetProfilePage> createState() => _PetProfilePageState();
}

class _PetProfilePageState extends State<PetProfilePage> {
  late Future<PetProfile> _futurePet;

  @override
  void initState() {
    super.initState();
    _futurePet = _loadPetProfile();
  }

  Future<PetProfile> _loadPetProfile() =>
      widget.profileLoader?.call(widget.mascotaId) ??
      _getPetProfile(widget.mascotaId);

  Future<PetProfile> _getPetProfile(int mascotaId) async {
    final Map<String, dynamic> mascota =
        await MascotasService.obtenerMascotaPorId(mascotaId: mascotaId);

    List<Map<String, dynamic>> imagenes = [];

    try {
      imagenes = await MascotasService.obtenerImagenesMascota(
        mascotaId: mascotaId,
      );
    } catch (error) {
      debugPrint('No se pudieron cargar imágenes de la mascota: $error');
    }

    mascota['fotos'] = imagenes;

    return PetProfile.fromJson(mascota);
  }

  Future<void> _goToEdit(PetProfile pet) async {
    final Map<String, dynamic> mascotaEditar = pet.toEditMap();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterPetPage(mascotaEditar: mascotaEditar),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      setState(() {
        _futurePet = _loadPetProfile();
      });
    }
  }

  Future<void> _confirmDeletePet(PetProfile pet) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeletePetDialog(
        petName: pet.nombre,
        onDelete: () => widget.deleteAction?.call(pet.id) ??
            MascotasService.eliminarMascota(mascotaId: pet.id),
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mascota eliminada correctamente')),
    );
    Navigator.pop(context, true);
  }

  void _openGallery(List<String> gallery, {int initialIndex = 0}) {
    if (gallery.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => initialIndex == 0
            ? ReportPhotoGalleryPage(
                photos: gallery,
                headers: MascotasService.authHeaders,
              )
            : ReportPhotoViewerPage(
                photos: gallery,
                initialIndex: initialIndex,
                headers: MascotasService.authHeaders,
              ),
      ),
    );
  }

  String _buildImageUrl(String? value) {
    if (value == null || value.trim().isEmpty) return '';

    final cleanValue = value.trim();

    if (cleanValue.startsWith('http://') || cleanValue.startsWith('https://')) {
      return cleanValue;
    }

    if (cleanValue.startsWith('/')) {
      return '${MascotasService.originUrl}$cleanValue';
    }

    return '${MascotasService.originUrl}/$cleanValue';
  }

  Color _statusColor(String estado) {
    switch (estado.toUpperCase()) {
      case 'PERDIDA':
        return Colors.red;
      case 'ENCONTRADA':
        return Colors.green;
      case 'INACTIVA':
        return Colors.grey;
      case 'ACTIVA':
      default:
        return const Color(0xFF4D9B6A);
    }
  }

  String _formatStatus(String estado) {
    if (estado.trim().isEmpty) return 'SIN ESTADO';
    return estado.toUpperCase();
  }

  String _formatSex(String sexo) {
    switch (sexo.toUpperCase()) {
      case 'MACHO':
        return 'Macho';
      case 'HEMBRA':
        return 'Hembra';
      case 'NO_DEFINIDO':
        return 'No definido';
      default:
        return sexo.isEmpty ? 'No definido' : sexo;
    }
  }

  String _formatAge(int? edad, String? unidad) {
    if (edad == null || edad <= 0) return 'No registrada';

    if (unidad == null || unidad.trim().isEmpty) {
      return '$edad';
    }

    final cleanUnidad = unidad.toUpperCase();

    if (cleanUnidad == 'ANIOS') {
      return edad == 1 ? '1 año' : '$edad años';
    }

    if (cleanUnidad == 'MESES') {
      return edad == 1 ? '1 mes' : '$edad meses';
    }

    return '$edad $unidad';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF7F0),
      drawer: const AniMapSideMenu(),

      body: SafeArea(
        child: FutureBuilder<PetProfile>(
          future: _futurePet,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              debugPrint('ERROR PERFIL MASCOTA: ${snapshot.error}');

              return _ErrorView(
                message:
                    'No se pudo cargar el perfil de la mascota\n${snapshot.error}',
                onRetry: () {
                  setState(() {
                    _futurePet = _loadPetProfile();
                  });
                },
              );
            }

            if (!snapshot.hasData) {
              return _ErrorView(
                message: 'No se encontró información de la mascota',
                onRetry: () {
                  setState(() {
                    _futurePet = _loadPetProfile();
                  });
                },
              );
            }

            final pet = snapshot.data!;

            final mainImage = _buildImageUrl(pet.mainPhotoUrl);

            final orderedPhotos = [
              ...pet.photos.where((photo) => photo.esPrincipal),
              ...pet.photos.where((photo) => !photo.esPrincipal),
            ];
            final gallery = orderedPhotos
                .map((photo) => _buildImageUrl(photo.urlPreview))
                .where((url) => url.isNotEmpty)
                .toList();

            return Column(
              children: [
                const TopMenuAnimap(),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: SizedBox()),

                            const Expanded(
                              flex: 3,
                              child: Text(
                                'Perfil de la Mascota',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                            ),

                            Expanded(
                              child: widget.mostrarAccionesDueno
                                  ? Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        tooltip: 'Eliminar mascota',
                                        onPressed: () {
                                          _confirmDeletePet(pet);
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                          size: 28,
                                        ),
                                      ),
                                    )
                                  : const SizedBox(),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 70,
                              backgroundColor: Colors.white,
                              child: ClipOval(
                                child: mainImage.isEmpty
                                    ? const Icon(
                                        Icons.pets,
                                        size: 70,
                                        color: Color(0xFF4D9B6A),
                                      )
                                    : Image.network(
                                        mainImage,
                                        headers: MascotasService.authHeaders,
                                        width: 132,
                                        height: 132,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) {
                                          return const Icon(
                                            Icons.pets,
                                            size: 70,
                                            color: Color(0xFF4D9B6A),
                                          );
                                        },
                                      ),
                              ),
                            ),

                            Positioned(
                              right: -22,
                              bottom: -8,
                              child: _StatusBadge(
                                text: _formatStatus(pet.estado),
                                color: _statusColor(pet.estado),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 34),

                        _PetInfoCard(
                          observaciones: pet.observaciones,
                          items: [
                            PetInfoItemData(
                              icon: Icons.pets,
                              title: 'Nombre',
                              value: pet.nombre,
                            ),
                            PetInfoItemData(
                              icon: Icons.category,
                              title: 'Especie',
                              value: pet.especie,
                            ),
                            PetInfoItemData(
                              icon: Icons.cruelty_free,
                              title: 'Raza',
                              value: pet.raza.isEmpty ? 'Sin raza' : pet.raza,
                            ),
                            PetInfoItemData(
                              icon: Icons.palette,
                              title: 'Color',
                              value: pet.color,
                            ),
                            PetInfoItemData(
                              icon: Icons.transgender,
                              title: 'Sexo',
                              value: _formatSex(pet.sexo),
                            ),
                            PetInfoItemData(
                              icon: Icons.cake,
                              title: 'Edad',
                              value: _formatAge(pet.edadAprox, pet.unidadEdad),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Galería de fotos',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        _GalleryRow(
                          gallery: gallery,
                          onOpenAll: () => _openGallery(gallery),
                          onOpenPhoto: (index) =>
                              _openGallery(gallery, initialIndex: index),
                        ),

                        if (widget.mostrarAccionesDueno) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _ActionButton(
                                  text: 'Editar',
                                  icon: Icons.edit,
                                  backgroundColor: const Color(0xFF4D9B6A),
                                  foregroundColor: Colors.white,
                                  onPressed: () {
                                    _goToEdit(pet);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),

      bottomNavigationBar: const BottomMenuAnimap(currentIndex: -1),
    );
  }
}

class PetProfile {
  final int id;
  final int fkUsuario;
  final int fkEspecie;
  final int? fkRaza;
  final String nombre;
  final String especie;
  final String raza;
  final String color;
  final String sexo;
  final String estado;
  final String observaciones;
  final int? edadAprox;
  final String? unidadEdad;
  final List<PetPhoto> photos;

  PetProfile({
    required this.id,
    required this.fkUsuario,
    required this.fkEspecie,
    required this.fkRaza,
    required this.nombre,
    required this.especie,
    required this.raza,
    required this.color,
    required this.sexo,
    required this.estado,
    required this.observaciones,
    required this.edadAprox,
    required this.unidadEdad,
    required this.photos,
  });

  String? get mainPhotoUrl {
    if (photos.isEmpty) return null;

    final principales = photos.where((photo) => photo.esPrincipal).toList();

    if (principales.isNotEmpty) {
      return principales.first.urlPreview;
    }

    return photos.first.urlPreview;
  }

  Map<String, dynamic> toEditMap() {
    return {
      'id': id,
      'fk_usuario': fkUsuario,
      'fk_especie': fkEspecie,
      'fk_raza': fkRaza,
      'nombre': nombre,
      'especie': especie,
      'raza': raza,
      'color': color,
      'edad_aprox': edadAprox,
      'unidad_edad': unidadEdad,
      'sexo': sexo,
      'estado': estado,
      'observaciones': observaciones,
      'imagenes': photos.map((photo) => photo.toMap()).toList(),
      'fotos': photos.map((photo) => photo.toMap()).toList(),
    };
  }

  factory PetProfile.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['fotos'] ?? json['imagenes'] ?? json['photos'] ?? [];

    return PetProfile(
      id: toInt(json['id'] ?? json['id_mascota'] ?? json['mascota_id']),
      fkUsuario: toInt(
        json['fk_usuario'] ??
            json['fkUsuario'] ??
            json['usuario_id'] ??
            json['id_usuario'],
      ),
      fkEspecie: toInt(
        json['fk_especie'] ??
            json['fkEspecie'] ??
            json['id_especie'] ??
            json['especie_id'],
      ),
      fkRaza: toNullableInt(
        json['fk_raza'] ?? json['fkRaza'] ?? json['id_raza'] ?? json['raza_id'],
      ),
      nombre: toStringValue(json['nombre']),
      especie: toStringValue(
        json['especie'] ?? json['nombre_especie'] ?? json['especie_nombre'],
      ),
      raza: toStringValue(
        json['raza'] ?? json['nombre_raza'] ?? json['raza_nombre'],
      ),
      color: toStringValue(json['color']),
      sexo: toStringValue(json['sexo']).isEmpty
          ? 'NO_DEFINIDO'
          : toStringValue(json['sexo']),
      estado: toStringValue(json['estado']).isEmpty
          ? 'ACTIVA'
          : toStringValue(json['estado']),
      observaciones: toStringValue(
        json['observaciones'] ?? json['senas'] ?? json['senas_particulares'],
      ),
      edadAprox: toNullableInt(
        json['edad_aprox'] ?? json['edadAprox'] ?? json['edad'],
      ),
      unidadEdad: toNullableString(json['unidad_edad'] ?? json['unidadEdad']),
      photos: parsePhotos(rawPhotos),
    );
  }

  static List<PetPhoto> parsePhotos(dynamic rawPhotos) {
    if (rawPhotos is! List) return [];

    return rawPhotos
        .whereType<Map>()
        .map(
          (item) => PetPhoto.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  static int toInt(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value;

    if (value is num) return value.toInt();

    if (value is String) {
      final cleanValue = value.trim();

      if (cleanValue.isEmpty) return 0;

      return int.tryParse(cleanValue) ?? 0;
    }

    return 0;
  }

  static int? toNullableInt(dynamic value) {
    if (value == null) return null;

    if (value is int) return value;

    if (value is num) return value.toInt();

    if (value is String) {
      final cleanValue = value.trim();

      if (cleanValue.isEmpty) return null;

      return int.tryParse(cleanValue);
    }

    return null;
  }

  static String toStringValue(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static String? toNullableString(dynamic value) {
    if (value == null) return null;

    final stringValue = value.toString().trim();

    if (stringValue.isEmpty) return null;

    return stringValue;
  }
}

class PetPhoto {
  final int id;
  final String storageRef;
  final String urlPreview;
  final bool esPrincipal;

  PetPhoto({
    required this.id,
    required this.storageRef,
    required this.urlPreview,
    required this.esPrincipal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storage_ref': storageRef,
      'url_preview': urlPreview,
      'es_principal': esPrincipal,
    };
  }

  factory PetPhoto.fromJson(Map<String, dynamic> json) {
    return PetPhoto(
      id: PetProfile.toInt(json['id']),
      storageRef: PetProfile.toStringValue(
        json['storage_ref'] ??
            json['storageRef'] ??
            json['path'] ??
            json['filename'],
      ),
      urlPreview: PetProfile.toStringValue(
        json['url_preview'] ??
            json['urlPreview'] ??
            json['url'] ??
            json['image_url'] ??
            json['imagen_url'],
      ),
      esPrincipal:
          json['es_principal'] == true ||
          json['esPrincipal'] == true ||
          json['principal'] == true,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFDDF5E9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.flag, color: color, size: 22),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: color,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class PetInfoItemData {
  final IconData icon;
  final String title;
  final String value;

  const PetInfoItemData({
    required this.icon,
    required this.title,
    required this.value,
  });
}

class _PetInfoCard extends StatelessWidget {
  final List<PetInfoItemData> items;
  final String observaciones;

  const _PetInfoCard({required this.items, required this.observaciones});

  @override
  Widget build(BuildContext context) {
    final cleanObservaciones = observaciones.trim().isEmpty
        ? 'Sin observaciones registradas'
        : observaciones.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFE7D3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 4,
              mainAxisExtent: 72,
            ),
            itemBuilder: (context, index) {
              final item = items[index];

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 28, color: const Color(0xFF4D9B6A)),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.value.isEmpty ? 'No registrado' : item.value,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black87,
                      height: 1.12,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7F0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFE7D3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.visibility,
                  size: 28,
                  color: Color(0xFF4D9B6A),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    textAlign: TextAlign.left,
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black, height: 1.2),
                      children: [
                        const TextSpan(
                          text: 'Observaciones o señas particulares:\n',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: cleanObservaciones,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryRow extends StatelessWidget {
  final List<String> gallery;
  final VoidCallback onOpenAll;
  final ValueChanged<int> onOpenPhoto;

  const _GalleryRow({
    required this.gallery,
    required this.onOpenAll,
    required this.onOpenPhoto,
  });

  @override
  Widget build(BuildContext context) {
    if (gallery.isEmpty) {
      return Container(
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'No hay fotos registradas',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }

    final hasMore = gallery.length > 4;
    final previewCount = hasMore ? 3 : gallery.length;
    final remaining = gallery.length - previewCount;

    return SizedBox(
      height: 66,
      child: Row(
        children: [
          for (int i = 0; i < previewCount; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: !hasMore && i == previewCount - 1 ? 0 : 8,
                ),
                child: InkWell(
                  key: ValueKey('pet-gallery-preview-$i'),
                  onTap: () => onOpenPhoto(i),
                  borderRadius: BorderRadius.circular(8),
                  child: _PetGalleryImage(url: gallery[i]),
                ),
              ),
            ),
          if (hasMore)
            Expanded(
              child: Semantics(
                button: true,
                label: 'Ver $remaining fotos más',
                child: InkWell(
                  key: const ValueKey('pet-gallery-more'),
                  onTap: onOpenAll,
                  borderRadius: BorderRadius.circular(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _PetGalleryImage(url: gallery[previewCount]),
                        ColoredBox(
                          color: const Color(0xBFFFFFFF),
                          child: Center(
                            child: Text(
                              '+$remaining',
                              key: const ValueKey('pet-gallery-more-count'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PetGalleryImage extends StatelessWidget {
  const _PetGalleryImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        headers: MascotasService.authHeaders,
        fit: BoxFit.cover,
        cacheWidth: 240,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: Colors.white,
          child: Icon(Icons.pets, color: Color(0xFF4D9B6A)),
        ),
      ),
    );
  }
}

class _DeletePetDialog extends StatefulWidget {
  const _DeletePetDialog({required this.petName, required this.onDelete});

  final String petName;
  final Future<void> Function() onDelete;

  @override
  State<_DeletePetDialog> createState() => _DeletePetDialogState();
}

class _DeletePetDialogState extends State<_DeletePetDialog> {
  bool _processing = false;
  String? _error;

  Future<void> _delete() async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await widget.onDelete();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = 'No se pudo eliminar la mascota. Inténtalo nuevamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processing,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '¿Eliminar mascota?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: Color(0xFF263238),
                  fontSize: 15,
                  height: 1.35,
                ),
                children: [
                  const TextSpan(text: 'Estás a punto de eliminar a '),
                  TextSpan(
                    text: widget.petName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const TextSpan(text: ' de tu cuenta.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta acción no se puede deshacer.',
              style: TextStyle(
                color: Color(0xFFC62828),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _processing ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-pet'),
            onPressed: _processing ? null : _delete,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: _processing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.text,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        elevation: 0,
        side: BorderSide(color: const Color(0xFF4D9B6A).withOpacity(0.45)),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 54, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
