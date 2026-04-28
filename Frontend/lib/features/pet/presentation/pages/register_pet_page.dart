import 'package:flutter/material.dart';
import '../../data/catalogos_service.dart';
import '../../../map/presentation/pages/map_page.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../data/mascotas_service.dart';

class RegisterPetPage extends StatefulWidget {
  const RegisterPetPage({super.key});

  @override
  State<RegisterPetPage> createState() => _RegisterPetPageState();
}

class _RegisterPetPageState extends State<RegisterPetPage> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _colorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _edadController = TextEditingController();

  bool _isLoading = false;
  bool _hasError = false;

  String? _especieSeleccionada;
  String? _razaSeleccionada;
  String? _sexoSeleccionado;

  String? _unidadEdadSeleccionada;

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
    _cargarCatalogosIniciales();
  }

  Future<void> _cargarCatalogosIniciales() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final especies = await CatalogosService.obtenerEspecies();
      final sexos = await CatalogosService.obtenerSexos();

      setState(() {
        _especies = especies;
        _sexos = sexos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error cargando catálogos'),
        ),
      );
    }
  }

  Future<void> _cargarRazasPorEspecie(int especieId) async {
    try {
      setState(() {
        _razaSeleccionadaId = null;
        _razas = [];
      });

      final razas = await CatalogosService.obtenerRazas(especieId);

      setState(() {
        _razas = razas;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error cargando razas'),
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

  List<Map<String, dynamic>> _especies = [];
  List<Map<String, dynamic>> _razas = [];
  List<Map<String, dynamic>> _sexos = [];

  int? _especieSeleccionadaId;
  int? _razaSeleccionadaId;
  String? _sexoSeleccionadoId;
  int? _fotoPrincipalIndex;

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

    if (_imagenesMascota.length < 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Debes cargar mínimo 15 fotos. Faltan ${15 - _imagenesMascota.length}.',
          ),
        ),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      await MascotasService.registrarMascota(
        fkUsuario: 1,
        fkEspecie: _especieSeleccionadaId!,
        fkRaza: _razaSeleccionadaId,
        nombre: _nombreController.text.trim(),
        color: _colorController.text.trim(),
        edadAprox: int.tryParse(_edadController.text.trim()),
        unidadEdad: _unidadEdadSeleccionada,
        sexo: _sexoSeleccionadoId ?? 'NO_DEFINIDO',
        observaciones: _observacionesController.text.trim(),
        imagenes: _imagenesMascota,
        fotoPrincipalIndex: _fotoPrincipalIndex ?? 0,
      );

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mascota registrada exitosamente'),
        ),
      );
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
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 105,
              width: double.infinity,
              color: lightGreen,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.menu, size: 36, color: Colors.black87),
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/Logo_Principal_AniMap.png',
                        height: 55,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'AniMap',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF344955),
                        ),
                      ),
                    ],
                  ),
                  const Icon(
                    Icons.notifications,
                    size: 36,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 140),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Registro de mascota',
                          style: TextStyle(
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

                      DropdownButtonFormField<int>(
                        value: _especieSeleccionadaId,
                        decoration: _inputDecoration(
                          hint: 'Especie',
                          prefixIcon: Icons.category,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasError,
                        ),
                        items: _especies.map((especie) {
                          return DropdownMenuItem<int>(
                            value: especie['id'],
                            child: Text(especie['nombre']),
                          );
                        }).toList(),
                        onChanged: _isLoading
                            ? null
                            : (value) {
                          if (value == null) return;

                          setState(() {
                            _especieSeleccionadaId = value;
                          });

                          _cargarRazasPorEspecie(value);
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'La especie es obligatoria';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      DropdownButtonFormField<int>(
                        value: _razaSeleccionadaId,
                        decoration: _inputDecoration(
                          hint: 'Raza',
                          prefixIcon: Icons.badge,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                        ),
                        items: _razas.map((raza) {
                          return DropdownMenuItem<int>(
                            value: raza['id'],
                            child: Text(raza['nombre']),
                          );
                        }).toList(),
                        onChanged: _isLoading || _especieSeleccionadaId == null
                            ? null
                            : (value) {
                          setState(() {
                            _razaSeleccionadaId = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        value: _sexoSeleccionadoId,
                        decoration: _inputDecoration(
                          hint: 'Sexo',
                          prefixIcon: Icons.transgender,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                        ),
                        items: _sexos.map((sexo) {
                          return DropdownMenuItem<String>(
                            value: sexo['id'],
                            child: Text(sexo['nombre']),
                          );
                        }).toList(),
                        onChanged: _isLoading
                            ? null
                            : (value) {
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
                              'Fotos cargadas: $fotosCargadas / 6',
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
                                onPressed: _isLoading
                                    ? null
                                    : _seleccionarImagenes,
                                icon: Icon(
                                  Icons.add_a_photo,
                                  color: accentGreen,
                                ),
                                label: Text(
                                  'Agregar foto',
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

                      if (_imagenesMascota.isNotEmpty)
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
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                              : const Text(
                            'Registrar mascota',
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
      bottomNavigationBar: Container(
        height: 95,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF7ECF9A),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MapPage(userName: '',),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.home,
                    size: 42,
                    color: Color(0xFF4D9B72),
                  ),
                ),

                const SizedBox(width: 80),

                IconButton(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.person,
                    size: 42,
                    color: Color(0xFF407F72),
                  ),
                ),
              ],
            ),

            Positioned(
              top: -5,
              child: Container(
                width: 105,
                height: 105,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F8F4),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF68B96D),
                          Color(0xFF09613D),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: const Icon(
                      Icons.pets,
                      color: Colors.white,
                      size: 45,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
