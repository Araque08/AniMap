import 'package:flutter/material.dart';
import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../data/catalogos_service.dart';
import '../../../map/presentation/pages/map_page.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../data/mascotas_service.dart';

class RegisterPetPage extends StatefulWidget {
  final Map<String, dynamic>? mascotaEditar;

  const RegisterPetPage({
    super.key,
    this.mascotaEditar,
  });

  @override
  State<RegisterPetPage> createState() => _RegisterPetPageState();
}

class _RegisterPetPageState extends State<RegisterPetPage> {

  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _colorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _edadController = TextEditingController();


  bool get isEditMode => widget.mascotaEditar != null;
  bool _isLoading = false;
  bool _hasError = false;

  List<Map<String, dynamic>> _especies = [];
  List<Map<String, dynamic>> _razas = [];

  List<Map<String, dynamic>> _imagenesExistentes = [];
  bool _isLoadingImages = false;

  int? _fotoPrincipalIndex;
  String? _unidadEdadSeleccionada;
  String? _especieSeleccionadaId;
  String? _razaSeleccionadaId;
  String? _sexoSeleccionadoId;

  final List<String> unidadesEdad = [
    'MESES',
    'ANIOS',
  ];

  final ImagePicker _picker = ImagePicker();
  List<XFile> _imagenesMascota = [];

  Future<void> _seleccionarImagenes() async {
    final List<XFile> imagenes = await _picker.pickMultiImage(
      imageQuality: 80,
    );

    if (imagenes.isNotEmpty) {
      setState(() {
        _imagenesMascota.addAll(imagenes);
        fotosCargadas = _imagenesMascota.length;

        _fotoPrincipalIndex ??= 0;
      });
    }
  }



  @override
  void initState() {
    super.initState();

    if (isEditMode) {
      _cargarDatosModoEdicion();
    } else {
      _cargarDatosIniciales();
    }
  }



  Future<void> _cargarRazasPorEspecie(
      int especieId, {
        String? razaSeleccionadaId,
      }) async {
    try {
      setState(() {
        _razas = [];
        _razaSeleccionadaId = null;
      });

      final razasResponse = await CatalogosService.obtenerRazas(especieId);

      final razasFinales = List<Map<String, dynamic>>.from(razasResponse);

      final existeRaza = razasFinales.any(
            (raza) => raza['id'].toString() == razaSeleccionadaId,
      );

      setState(() {
        _razas = razasFinales;

        // Aquí usas el valor que llegó desde BD
        _razaSeleccionadaId = existeRaza ? razaSeleccionadaId : null;
      });

      print('RAZA QUE VIENE DE BD: $razaSeleccionadaId');
      print('RAZA FINAL EN DROPDOWN: $_razaSeleccionadaId');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error cargando razas'),
        ),
      );
    }
  }


  Future<void> _cargarDatosModoEdicion() async {
    final pet = widget.mascotaEditar!;

    print('Mascota recibida para editar: $pet');

    setState(() {
      _isLoading = true;
    });

    try {
      _nombreController.text = pet['nombre']?.toString() ?? '';
      _colorController.text = pet['color']?.toString() ?? '';
      _observacionesController.text = pet['observaciones']?.toString() ?? '';
      _edadController.text = pet['edad_aprox']?.toString() ?? '';

      final especieId = pet['fk_especie']?.toString();
      final razaId = pet['fk_raza']?.toString();

      final especiesResponse = await CatalogosService.obtenerEspecies();

      setState(() {
        _especies = especiesResponse;
        _unidadEdadSeleccionada = pet['unidad_edad']?.toString();
        _sexoSeleccionadoId = pet['sexo']?.toString() ?? 'NO_DEFINIDO';
        _especieSeleccionadaId = especieId;
      });

      if (especieId != null && especieId.isNotEmpty) {
        await _cargarRazasPorEspecie(
          int.parse(especieId),
          razaSeleccionadaId: razaId,
        );
      }

      await _cargarImagenesExistentes();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando datos de la mascota: $e'),
        ),
      );
    }
  }

  Future<void> _cargarDatosIniciales() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final especiesResponse = await CatalogosService.obtenerEspecies();

      setState(() {
        _especies = especiesResponse;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando especies: $e'),
        ),
      );
    }
  }



  Future<void> _cargarImagenesExistentes() async {
    if (!isEditMode) return;

    final pet = widget.mascotaEditar!;
    final mascotaId = pet['id'];
    const usuarioId = 1;

    if (mascotaId == null) return;

    try {
      setState(() {
        _isLoadingImages = true;
      });

      final imagenes = await MascotasService.obtenerImagenesMascota(
        mascotaId: int.parse(mascotaId.toString()),
        usuarioId: usuarioId,
      );

      setState(() {
        _imagenesExistentes = imagenes;
        _isLoadingImages = false;
      });
    } catch (e) {
      print('ERROR CARGANDO FOTOS DE LA MASCOTA: $e');

      setState(() {
      _isLoadingImages = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
      content: Text('Error cargando fotos: $e'),
      ),
      );
      }
  }



  int fotosCargadas = 0;

  final Color primaryGreen = const Color(0xFF4FA37A);
  final Color accentGreen = const Color(0xFF09613D);
  final Color lightGreen = const Color(0xFFDDF3E9);
  final Color background = const Color(0xFFF7FFF9);
  final Color hintText = const Color(0xFF6B6B6B);

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    required Color hintTextColor,
    required Color iconColor,
    bool hasError = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: hintTextColor,
        fontSize: 15,
      ),
      prefixIcon: Icon(
        prefixIcon,
        color: hasError ? Colors.red : iconColor,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: hasError ? Colors.red : const Color(0xFFB8DCCB),
          width: 1.4,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: hasError ? Colors.red : accentGreen,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Colors.red,
          width: 1.4,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Colors.red,
          width: 2,
        ),
      ),
    );
  }

  Widget _buildImagenesExistentes() {
    if (!isEditMode) {
      return const SizedBox.shrink();
    }

    if (_isLoadingImages) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_imagenesExistentes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFA7F3D0),
          ),
        ),
        child: const Text(
          'Esta mascota aún no tiene fotos cargadas.',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13,
          ),
        ),
      );
    }

    return SizedBox(
      height: 105,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _imagenesExistentes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final imagen = _imagenesExistentes[index];

          final imageUrl =
              '${MascotasService.baseUrl.replaceAll('/api', '')}${imagen['url']}';

          final esPrincipal = imagen['esPrincipal'] == true;

          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  imageUrl,
                  width: 95,
                  height: 95,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 95,
                      height: 95,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.pets,
                        color: Color(0xFF6B7280),
                      ),
                    );
                  },
                ),
              ),
              if (esPrincipal)
                Positioned(
                  left: 6,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF047857),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Principal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _guardarMascota() async {
    setState(() {
      _hasError = false;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _hasError = true;
      });
      return;
    }

    if (_especieSeleccionadaId == null || _especieSeleccionadaId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar una especie'),
        ),
      );
      return;
    }

    final totalFotosDisponibles =
        _imagenesExistentes.length + _imagenesMascota.length;

    if (!isEditMode && _imagenesMascota.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes agregar mínimo 6 fotos para registrar la mascota'),
        ),
      );
      return;
    }

    if (isEditMode && totalFotosDisponibles == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La mascota debe conservar al menos una foto'),
        ),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final fkRaza = _razaSeleccionadaId == null || _razaSeleccionadaId!.isEmpty
          ? null
          : int.tryParse(_razaSeleccionadaId!);

      final edadAprox = _edadController.text.trim().isEmpty
          ? null
          : int.tryParse(_edadController.text.trim());

      if (isEditMode) {
        final mascotaId = int.parse(
          widget.mascotaEditar!['id'].toString(),
        );

        await MascotasService.actualizarMascota(
          mascotaId: mascotaId,
          fkUsuario: 1,
          fkEspecie: int.parse(_especieSeleccionadaId!),
          fkRaza: fkRaza,
          nombre: _nombreController.text.trim(),
          color: _colorController.text.trim(),
          edadAprox: edadAprox,
          unidadEdad: _unidadEdadSeleccionada,
          sexo: _sexoSeleccionadoId ?? 'NO_DEFINIDO',
          observaciones: _observacionesController.text.trim(),
        );

        if (_imagenesMascota.isNotEmpty) {
          await MascotasService.agregarFotosMascota(
            mascotaId: mascotaId,
            fkUsuario: 1,
            imagenes: _imagenesMascota,
            fotoPrincipalIndex: _fotoPrincipalIndex ?? 0,
            marcarComoPrincipal: _fotoPrincipalIndex != null,
          );
        }

        setState(() {
          _isLoading = false;
        });

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mascota actualizada correctamente'),
          ),
        );

        Navigator.pop(context, true);
        return;
      }

      await MascotasService.registrarMascota(
        fkUsuario: 1,
        fkEspecie: int.parse(_especieSeleccionadaId!),
        fkRaza: fkRaza,
        nombre: _nombreController.text.trim(),
        color: _colorController.text.trim(),
        edadAprox: edadAprox,
        unidadEdad: _unidadEdadSeleccionada,
        sexo: _sexoSeleccionadoId ?? 'NO_DEFINIDO',
        observaciones: _observacionesController.text.trim(),
        imagenes: _imagenesMascota,
        fotoPrincipalIndex: _fotoPrincipalIndex ?? 0,
      );

      setState(() {
        _isLoading = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mascota registrada exitosamente'),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: background,
      drawer: const AniMapSideMenu(),
      body: SafeArea(
        child: Column(
          children: [
            const TopMenuAnimap(),

            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 140),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(isEditMode ? 'Editar Mascota' : 'Registrar Mascota',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF263238),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Completa la información básica de tu mascota.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B6B6B),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      TextFormField(
                        controller: _nombreController,
                        enabled: !_isLoading,
                        decoration: _inputDecoration(
                          hint: 'Nombre de la mascota',
                          prefixIcon: Icons.pets,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasError,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El nombre es obligatorio';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _especieSeleccionadaId,
                        isExpanded: true,
                        decoration: _inputDecoration(
                          hint: 'Especie',
                          prefixIcon: Icons.pets,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasError,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'La especie es obligaroria';
                          }
                          return null;
                        },
                        items: _especies.map((especie) {
                          return DropdownMenuItem<String>(
                            value: especie['id'].toString(),
                            child: Text(especie['nombre'].toString()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _especieSeleccionadaId = value;
                            _razaSeleccionadaId = null;
                          });

                          if (value != null) {
                            _cargarRazasPorEspecie(int.parse(value));
                          }
                        },
                      ),

                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _razaSeleccionadaId,
                        isExpanded: true,
                        decoration: _inputDecoration(
                          hint: 'Raza',
                          prefixIcon: Icons.pets,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasError,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'La raza es obligatoria';
                          }
                          return null;
                        },
                        items: _razas.map((raza) {
                          return DropdownMenuItem<String>(
                            value: raza['id'].toString(),
                            child: Text(raza['nombre'].toString()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _razaSeleccionadaId = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _sexoSeleccionadoId,
                        isExpanded: true,
                        decoration: _inputDecoration(
                          hint: 'Sexo',
                          prefixIcon: Icons.pets,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasError,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El sexo es obligatorio';
                          }
                          return null;
                        },
                        items: const [
                          DropdownMenuItem(
                            value: 'MACHO',
                            child: Text('Macho'),
                          ),
                          DropdownMenuItem(
                            value: 'HEMBRA',
                            child: Text('Hembra'),
                          ),
                          DropdownMenuItem(
                            value: 'NO_DEFINIDO',
                            child: Text('No definido'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _sexoSeleccionadoId = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _unidadEdadSeleccionada,
                        decoration: _inputDecoration(
                          hint: 'Unidad de edad',
                          prefixIcon: Icons.calendar_month,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasError,
                        ),
                        items: unidadesEdad.map((unidad) {
                          return DropdownMenuItem<String>(
                            value: unidad,
                            child: Text(
                              unidad == 'MESES' ? 'Meses' : 'Años',
                            ),
                          );
                        }).toList(),
                        onChanged: _isLoading
                            ? null
                            : (value) {
                          setState(() {
                            _unidadEdadSeleccionada = value;
                          });
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'La unidad de edad es obligatoria';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _edadController,
                        keyboardType: TextInputType.number,
                        enabled: !_isLoading,
                        decoration: _inputDecoration(
                          hint: 'Edad',
                          prefixIcon: Icons.pets,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasError,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'La edad es obligatoria';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _colorController,
                        enabled: !_isLoading,
                        decoration: _inputDecoration(
                          hint: 'Color principal',
                          prefixIcon: Icons.color_lens,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasError,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El color es obligatorio';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _observacionesController,
                        enabled: !_isLoading,
                        maxLines: 3,
                        decoration: _inputDecoration(
                          hint: 'Observaciones o señas particulares',
                          prefixIcon: Icons.notes,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                        ),
                      ),

                      const SizedBox(height: 20),

                      const SizedBox(height: 20),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFB8DCCB),
                            width: 1.4,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              isEditMode
                                  ? 'Fotos actuales y nuevas'
                                  : 'Fotos cargadas: $fotosCargadas / 6',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF263238),
                              ),
                            ),

                            const SizedBox(height: 10),

                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : _seleccionarImagenes,
                                icon: Icon(
                                  Icons.add_a_photo,
                                  color: accentGreen,
                                ),
                                label: Text(
                                  isEditMode ? 'Agregar nuevas fotos' : 'Agregar foto',
                                  style: TextStyle(
                                    color: accentGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: accentGreen,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      if (isEditMode) _buildImagenesExistentes(),

                      if (isEditMode) const SizedBox(height: 18),

                      if (_imagenesMascota.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Fotos nuevas seleccionadas',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF263238),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _imagenesMascota.length,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemBuilder: (context, index) {
                                final imagen = _imagenesMascota[index];

                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(imagen.path),
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),

                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _imagenesMascota.removeAt(index);
                                            fotosCargadas = _imagenesMascota.length;

                                            if (_imagenesMascota.isEmpty) {
                                              _fotoPrincipalIndex = null;
                                            } else if (_fotoPrincipalIndex == index) {
                                              _fotoPrincipalIndex = 0;
                                            } else if (_fotoPrincipalIndex != null &&
                                                index < _fotoPrincipalIndex!) {
                                              _fotoPrincipalIndex = _fotoPrincipalIndex! - 1;
                                            }
                                          });
                                        },
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          padding: const EdgeInsets.all(4),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),

                                    Positioned(
                                      left: 4,
                                      bottom: 4,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _fotoPrincipalIndex = index;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _fotoPrincipalIndex == index
                                                ? accentGreen
                                                : Colors.black54,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            _fotoPrincipalIndex == index ? 'Principal' : 'Elegir',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),

                      const SizedBox(height: 26),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _guardarMascota,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentGreen,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                              : Text(isEditMode ? 'Editar Mascota' : 'Registrar Mascota',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuAnimap(
        currentIndex: 1,
      ),
    );
  }
}
