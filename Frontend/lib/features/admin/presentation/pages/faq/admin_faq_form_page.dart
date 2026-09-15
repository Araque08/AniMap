import 'package:flutter/material.dart';

import '../../../data/faq_service.dart';

class AdminFaqFormPage extends StatefulWidget {
  /*
    Si faq es null, estamos CREANDO.
    Si faq contiene información, estamos EDITANDO.
  */
  final Map<String, dynamic>? faq;

  const AdminFaqFormPage({
    super.key,
    this.faq,
  });

  @override
  State<AdminFaqFormPage> createState() =>
      _AdminFaqFormPageState();
}

class _AdminFaqFormPageState
    extends State<AdminFaqFormPage> {
  /*
    ============================================================
    COLORES ANIMAP
    ============================================================
  */

  static const Color lightGreen =
  Color(0xFFDFF3E8);

  static const Color darkText =
  Color(0xFF344955);

  static const Color accentGreen =
  Color(0xFF3F9568);

  static const Color backgroundColor =
  Color(0xFFF7FAF8);

  /*
    ============================================================
    SERVICIO
    ============================================================
  */

  final FaqService _faqService =
  FaqService();

  /*
    ============================================================
    FORMULARIO
    ============================================================
  */

  final GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  final TextEditingController
  _preguntaController =
  TextEditingController();

  final TextEditingController
  _respuestaController =
  TextEditingController();

  /*
    ============================================================
    ESTADO
    ============================================================
  */

  List<Map<String, dynamic>>
  _categorias = [];

  int? _categoriaSeleccionada;

  bool _activa = true;

  bool _isLoading = true;

  bool _isSaving = false;

  String? _errorMessage;

  /*
    Si recibimos una FAQ, la pantalla
    se encuentra en modo edición.
  */
  bool get _isEditing =>
      widget.faq != null;

  @override
  void initState() {
    super.initState();

    _prepararFormulario();
  }

  @override
  void dispose() {
    _preguntaController.dispose();
    _respuestaController.dispose();

    super.dispose();
  }

  /*
    ============================================================
    PREPARAR FORMULARIO
    ============================================================
  */

  Future<void> _prepararFormulario() async {
    /*
      Si estamos editando, primero cargamos
      la información que ya tiene la FAQ.
    */

    if (_isEditing) {
      final faq = widget.faq!;

      _preguntaController.text =
          faq['pregunta']
              ?.toString() ??
              '';

      _respuestaController.text =
          faq['respuesta']
              ?.toString() ??
              '';

      _categoriaSeleccionada =
          int.tryParse(
            faq['fk_categoria']
                .toString(),
          );

      _activa =
          faq['activa'] == true;
    }

    await _cargarCategorias();
  }

  /*
    ============================================================
    CARGAR CATEGORÍAS
    ============================================================
  */

  Future<void> _cargarCategorias() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final categorias =
      await _faqService
          .getCategories();

      if (!mounted) return;

      setState(() {
        _categorias = categorias;
        _isLoading = false;
      });
    } on FaqException catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;

        _errorMessage =
        'No se pudieron cargar las categorías';
      });
    }
  }

  /*
    ============================================================
    GUARDAR
    ============================================================
  */

  Future<void> _guardar() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();

    /*
      Validamos todos los campos.
    */
    final formularioValido =
        _formKey.currentState
            ?.validate() ??
            false;

    if (!formularioValido) {
      return;
    }

    /*
      La categoría también es obligatoria.
    */
    if (_categoriaSeleccionada ==
        null) {
      _mostrarMensaje(
        'Selecciona una categoría',
        isError: true,
      );

      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      /*
        ========================================================
        EDITAR
        ========================================================
      */

      if (_isEditing) {
        final id = int.tryParse(
          widget.faq!['id']
              .toString(),
        );

        if (id == null) {
          throw FaqException(
            'No se pudo identificar la pregunta frecuente',
          );
        }

        await _faqService.updateFaq(
          id: id,
          categoriaId:
          _categoriaSeleccionada!,
          pregunta:
          _preguntaController.text,
          respuesta:
          _respuestaController.text,
          activa: _activa,
        );

        if (!mounted) return;

        _mostrarMensaje(
          'Pregunta frecuente actualizada correctamente',
        );

        /*
          true indica a la pantalla anterior
          que debe actualizar el listado.
        */
        Navigator.pop(
          context,
          true,
        );

        return;
      }

      /*
        ========================================================
        CREAR
        ========================================================
      */

      await _faqService.createFaq(
        categoriaId:
        _categoriaSeleccionada!,
        pregunta:
        _preguntaController.text,
        respuesta:
        _respuestaController.text,
        activa: _activa,
      );

      if (!mounted) return;

      _mostrarMensaje(
        'Pregunta frecuente creada correctamente',
      );

      Navigator.pop(
        context,
        true,
      );
    } on FaqException catch (e) {
      if (!mounted) return;

      _mostrarMensaje(
        e.message,
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje(
        _isEditing
            ? 'No se pudo actualizar la pregunta frecuente'
            : 'No se pudo crear la pregunta frecuente',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /*
    ============================================================
    MENSAJES
    ============================================================
  */

  void _mostrarMensaje(
      String mensaje, {
        bool isError = false,
      }) {
    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor:
        isError
            ? Colors.red.shade700
            : accentGreen,
      ),
    );
  }

  /*
    ============================================================
    DISEÑO
    ============================================================
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
      backgroundColor,

      /*
        ========================================================
        APP BAR
        ========================================================
      */

      appBar: AppBar(
        backgroundColor:
        lightGreen,
        foregroundColor:
        darkText,
        elevation: 0,
        title: Text(
          _isEditing
              ? 'Editar pregunta'
              : 'Nueva pregunta',
          style: const TextStyle(
            fontWeight:
            FontWeight.w700,
          ),
        ),
      ),

      body: SafeArea(
        child: _isLoading
            ? const Center(
          child:
          CircularProgressIndicator(
            color:
            accentGreen,
          ),
        )
            : _errorMessage !=
            null
            ? _buildError()
            : _buildForm(),
      ),
    );
  }

  /*
    ============================================================
    FORMULARIO
    ============================================================
  */

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding:
        const EdgeInsets.fromLTRB(
          18,
          20,
          18,
          35,
        ),
        children: [
          /*
            ====================================================
            INFORMACIÓN
            ====================================================
          */

          Container(
            padding:
            const EdgeInsets.all(
              17,
            ),
            decoration:
            BoxDecoration(
              color: lightGreen,
              borderRadius:
              BorderRadius.circular(
                17,
              ),
            ),
            child: Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration:
                  BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius
                        .circular(
                      13,
                    ),
                  ),
                  child: Icon(
                    _isEditing
                        ? Icons
                        .edit_note_rounded
                        : Icons
                        .help_outline_rounded,
                    color:
                    accentGreen,
                  ),
                ),
                const SizedBox(
                  width: 13,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        _isEditing
                            ? 'Actualizar FAQ'
                            : 'Crear una FAQ',
                        style:
                        const TextStyle(
                          color:
                          darkText,
                          fontSize:
                          17,
                          fontWeight:
                          FontWeight
                              .w700,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        _isEditing
                            ? 'Modifica la información necesaria y guarda los cambios.'
                            : 'Completa la categoría, pregunta y respuesta que aparecerán en la ayuda de AniMap.',
                        style:
                        const TextStyle(
                          color:
                          Colors
                              .black54,
                          fontSize:
                          13,
                          height:
                          1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 24,
          ),

          /*
            ====================================================
            CATEGORÍA
            ====================================================
          */

          const Text(
            'Categoría',
            style: TextStyle(
              color: darkText,
              fontSize: 15,
              fontWeight:
              FontWeight.w700,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          DropdownButtonFormField<
              int>(
            value:
            _categoriaSeleccionada,
            isExpanded: true,
            decoration:
            _inputDecoration(
              hint:
              'Selecciona una categoría',
              icon:
              Icons.category_outlined,
            ),
            items:
            _categorias.map(
                  (categoria) {
                final id =
                int.tryParse(
                  categoria['id']
                      .toString(),
                );

                if (id == null) {
                  return const DropdownMenuItem<
                      int>(
                    value: -1,
                    child: Text(
                      'Categoría inválida',
                    ),
                  );
                }

                return DropdownMenuItem<
                    int>(
                  value: id,
                  child: Text(
                    categoria[
                    'nombre']
                        ?.toString() ??
                        'Sin nombre',
                  ),
                );
              },
            ).toList(),
            onChanged:
            _isSaving
                ? null
                : (value) {
              setState(
                    () {
                  _categoriaSeleccionada =
                      value;
                },
              );
            },
            validator: (value) {
              if (value ==
                  null ||
                  value == -1) {
                return 'Selecciona una categoría';
              }

              return null;
            },
          ),

          /*
            Si no existen categorías, mostramos
            un aviso al administrador.
          */

          if (_categorias
              .isEmpty) ...[
            const SizedBox(
              height: 8,
            ),
            const Text(
              'No existen categorías. Primero debes crear una categoría FAQ.',
              style: TextStyle(
                color:
                Colors.orange,
                fontSize: 12,
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(
            height: 22,
          ),

          /*
            ====================================================
            PREGUNTA
            ====================================================
          */

          const Text(
            'Pregunta',
            style: TextStyle(
              color: darkText,
              fontSize: 15,
              fontWeight:
              FontWeight.w700,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          TextFormField(
            controller:
            _preguntaController,
            enabled: !_isSaving,
            textCapitalization:
            TextCapitalization
                .sentences,
            maxLines: 3,
            minLines: 1,
            maxLength: 300,
            decoration:
            _inputDecoration(
              hint:
              'Ej. ¿Cómo registro una mascota?',
              icon:
              Icons.help_outline,
            ),
            validator: (value) {
              if (value == null ||
                  value
                      .trim()
                      .isEmpty) {
                return 'Ingresa la pregunta';
              }

              if (value
                  .trim()
                  .length <
                  5) {
                return 'La pregunta es demasiado corta';
              }

              return null;
            },
          ),

          const SizedBox(
            height: 14,
          ),

          /*
            ====================================================
            RESPUESTA
            ====================================================
          */

          const Text(
            'Respuesta',
            style: TextStyle(
              color: darkText,
              fontSize: 15,
              fontWeight:
              FontWeight.w700,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          TextFormField(
            controller:
            _respuestaController,
            enabled: !_isSaving,
            textCapitalization:
            TextCapitalization
                .sentences,
            minLines: 5,
            maxLines: 8,
            maxLength: 1000,
            decoration:
            _inputDecoration(
              hint:
              'Escribe una respuesta clara para el usuario...',
              icon:
              Icons.subject_rounded,
            ),
            validator: (value) {
              if (value == null ||
                  value
                      .trim()
                      .isEmpty) {
                return 'Ingresa la respuesta';
              }

              if (value
                  .trim()
                  .length <
                  5) {
                return 'La respuesta es demasiado corta';
              }

              return null;
            },
          ),

          const SizedBox(
            height: 10,
          ),

          /*
            ====================================================
            ESTADO
            ====================================================
          */

          Container(
            decoration:
            BoxDecoration(
              color: Colors.white,
              borderRadius:
              BorderRadius.circular(
                15,
              ),
              border: Border.all(
                color:
                Colors.grey.shade200,
              ),
            ),
            child: SwitchListTile(
              value: _activa,
              activeColor:
              accentGreen,
              onChanged:
              _isSaving
                  ? null
                  : (value) {
                setState(
                      () {
                    _activa =
                        value;
                  },
                );
              },
              secondary: Icon(
                _activa
                    ? Icons
                    .visibility_outlined
                    : Icons
                    .visibility_off_outlined,
                color: _activa
                    ? accentGreen
                    : Colors
                    .black45,
              ),
              title: Text(
                _activa
                    ? 'FAQ activa'
                    : 'FAQ archivada',
                style:
                const TextStyle(
                  color: darkText,
                  fontWeight:
                  FontWeight
                      .w700,
                ),
              ),
              subtitle: Text(
                _activa
                    ? 'La pregunta será visible para los usuarios.'
                    : 'La pregunta no aparecerá en la sección pública.',
              ),
            ),
          ),

          const SizedBox(
            height: 28,
          ),

          /*
            ====================================================
            BOTÓN GUARDAR
            ====================================================
          */

          SizedBox(
            height: 54,
            child:
            ElevatedButton.icon(
              onPressed:
              _isSaving ||
                  _categorias
                      .isEmpty
                  ? null
                  : _guardar,
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                accentGreen,
                foregroundColor:
                Colors.white,
                disabledBackgroundColor:
                accentGreen
                    .withOpacity(
                  0.45,
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    15,
                  ),
                ),
                elevation: 0,
              ),
              icon: _isSaving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child:
                CircularProgressIndicator(
                  strokeWidth:
                  2.3,
                  color:
                  Colors.white,
                ),
              )
                  : Icon(
                _isEditing
                    ? Icons
                    .save_outlined
                    : Icons
                    .add_circle_outline,
              ),
              label: Text(
                _isSaving
                    ? 'Guardando...'
                    : _isEditing
                    ? 'Guardar cambios'
                    : 'Crear pregunta',
                style:
                const TextStyle(
                  fontSize: 16,
                  fontWeight:
                  FontWeight
                      .w700,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          /*
            ====================================================
            CANCELAR
            ====================================================
          */

          SizedBox(
            height: 50,
            child:
            OutlinedButton(
              onPressed:
              _isSaving
                  ? null
                  : () {
                Navigator.pop(
                  context,
                );
              },
              style:
              OutlinedButton.styleFrom(
                foregroundColor:
                darkText,
                side: BorderSide(
                  color:
                  Colors.grey.shade300,
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    15,
                  ),
                ),
              ),
              child:
              const Text(
                'Cancelar',
                style:
                TextStyle(
                  fontWeight:
                  FontWeight
                      .w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /*
    ============================================================
    DECORACIÓN DE CAMPOS
    ============================================================
  */

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: accentGreen,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 16,
      ),
      border:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        borderSide:
        BorderSide.none,
      ),
      enabledBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        borderSide: BorderSide(
          color:
          Colors.grey.shade200,
        ),
      ),
      focusedBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        borderSide:
        const BorderSide(
          color: accentGreen,
          width: 1.4,
        ),
      ),
      errorBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        borderSide:
        const BorderSide(
          color: Colors.redAccent,
        ),
      ),
      focusedErrorBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          15,
        ),
        borderSide:
        const BorderSide(
          color: Colors.redAccent,
          width: 1.4,
        ),
      ),
    );
  }

  /*
    ============================================================
    ERROR AL CARGAR CATEGORÍAS
    ============================================================
  */

  Widget _buildError() {
    return Center(
      child:
      SingleChildScrollView(
        padding:
        const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment
              .center,
          children: [
            Icon(
              Icons
                  .error_outline_rounded,
              size: 55,
              color:
              Colors.red.shade400,
            ),
            const SizedBox(
              height: 15,
            ),
            Text(
              _errorMessage ??
                  'Ocurrió un error',
              textAlign:
              TextAlign.center,
              style:
              const TextStyle(
                color: darkText,
                fontSize: 15,
                fontWeight:
                FontWeight
                    .w600,
              ),
            ),
            const SizedBox(
              height: 18,
            ),
            ElevatedButton.icon(
              onPressed:
              _cargarCategorias,
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                accentGreen,
                foregroundColor:
                Colors.white,
              ),
              icon:
              const Icon(
                Icons
                    .refresh_rounded,
              ),
              label:
              const Text(
                'Reintentar',
              ),
            ),
          ],
        ),
      ),
    );
  }
}