import 'package:flutter/material.dart';

import '../../../data/faq_service.dart';

class AdminFaqCategoriesPage extends StatefulWidget {
  const AdminFaqCategoriesPage({super.key});

  @override
  State<AdminFaqCategoriesPage> createState() =>
      _AdminFaqCategoriesPageState();
}

class _AdminFaqCategoriesPageState
    extends State<AdminFaqCategoriesPage> {
  static const Color lightGreen = Color(0xFFDFF3E8);
  static const Color darkText = Color(0xFF344955);
  static const Color accentGreen = Color(0xFF3F9568);
  static const Color backgroundColor = Color(0xFFF7FAF8);

  final FaqService _faqService = FaqService();

  List<Map<String, dynamic>> _categorias = [];

  bool _isLoading = true;
  bool _isProcessing = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
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
      await _faqService.getCategories();

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
    CREAR CATEGORÍA
    ============================================================
  */

  Future<void> _crearCategoria() async {
    await _mostrarFormularioCategoria();
  }

  /*
    ============================================================
    EDITAR CATEGORÍA
    ============================================================
  */

  Future<void> _editarCategoria(
      Map<String, dynamic> categoria,
      ) async {
    await _mostrarFormularioCategoria(
      categoria: categoria,
    );
  }

  /*
    ============================================================
    FORMULARIO CREAR / EDITAR
    ============================================================
  */

  Future<void> _mostrarFormularioCategoria({
    Map<String, dynamic>? categoria,
  }) async {
    final formKey = GlobalKey<FormState>();

    final nombreController =
    TextEditingController(
      text: categoria?['nombre']?.toString() ?? '',
    );

    final descripcionController =
    TextEditingController(
      text:
      categoria?['descripcion']?.toString() ?? '',
    );

    final isEditing = categoria != null;

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: !_isProcessing,
      builder: (dialogContext) {
        bool guardando = false;

        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            Future<void> guardar() async {
              if (guardando) return;

              final valido =
                  formKey.currentState?.validate() ??
                      false;

              if (!valido) return;

              setDialogState(() {
                guardando = true;
              });

              try {
                if (isEditing) {
                  final id = int.tryParse(
                    categoria['id'].toString(),
                  );

                  if (id == null) {
                    throw FaqException(
                      'No se pudo identificar la categoría',
                    );
                  }

                  await _faqService.updateCategory(
                    id: id,
                    nombre:
                    nombreController.text,
                    descripcion:
                    descripcionController.text
                        .trim()
                        .isEmpty
                        ? null
                        : descripcionController.text,
                  );
                } else {
                  await _faqService.createCategory(
                    nombre:
                    nombreController.text,
                    descripcion:
                    descripcionController.text
                        .trim()
                        .isEmpty
                        ? null
                        : descripcionController.text,
                  );
                }

                if (!dialogContext.mounted) return;

                Navigator.pop(
                  dialogContext,
                  true,
                );
              } on FaqException catch (e) {
                if (!dialogContext.mounted) return;

                ScaffoldMessenger.of(context)
                    .hideCurrentSnackBar();

                ScaffoldMessenger.of(context)
                    .showSnackBar(
                  SnackBar(
                    content: Text(e.message),
                    backgroundColor:
                    Colors.red.shade700,
                  ),
                );

                setDialogState(() {
                  guardando = false;
                });
              } catch (_) {
                if (!dialogContext.mounted) return;

                ScaffoldMessenger.of(context)
                    .hideCurrentSnackBar();

                ScaffoldMessenger.of(context)
                    .showSnackBar(
                  SnackBar(
                    content: Text(
                      isEditing
                          ? 'No se pudo actualizar la categoría'
                          : 'No se pudo crear la categoría',
                    ),
                    backgroundColor:
                    Colors.red.shade700,
                  ),
                );

                setDialogState(() {
                  guardando = false;
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: lightGreen,
                      borderRadius:
                      BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEditing
                          ? Icons.edit_outlined
                          : Icons.add_rounded,
                      color: accentGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing
                          ? 'Editar categoría'
                          : 'Nueva categoría',
                      style: const TextStyle(
                        color: darkText,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nombre',
                        style: TextStyle(
                          color: darkText,
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller:
                        nombreController,
                        enabled: !guardando,
                        textCapitalization:
                        TextCapitalization.words,
                        maxLength: 100,
                        decoration:
                        _inputDecoration(
                          hint:
                          'Ej. Cuenta y acceso',
                          icon:
                          Icons.category_outlined,
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return 'Ingresa el nombre de la categoría';
                          }

                          if (value.trim().length < 3) {
                            return 'El nombre es demasiado corto';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Descripción',
                        style: TextStyle(
                          color: darkText,
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller:
                        descripcionController,
                        enabled: !guardando,
                        textCapitalization:
                        TextCapitalization.sentences,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 255,
                        decoration:
                        _inputDecoration(
                          hint:
                          'Describe brevemente esta categoría',
                          icon:
                          Icons.subject_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: guardando
                      ? null
                      : () {
                    Navigator.pop(
                      dialogContext,
                      false,
                    );
                  },
                  child: const Text(
                    'Cancelar',
                  ),
                ),
                ElevatedButton(
                  onPressed:
                  guardando ? null : guardar,
                  style:
                  ElevatedButton.styleFrom(
                    backgroundColor:
                    accentGreen,
                    foregroundColor:
                    Colors.white,
                  ),
                  child: guardando
                      ? const SizedBox(
                    width: 19,
                    height: 19,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                      : Text(
                    isEditing
                        ? 'Guardar'
                        : 'Crear',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nombreController.dispose();
    descripcionController.dispose();

    if (resultado == true && mounted) {
      _mostrarMensaje(
        isEditing
            ? 'Categoría actualizada correctamente'
            : 'Categoría creada correctamente',
      );

      await _cargarCategorias();
    }
  }

  /*
    ============================================================
    ELIMINAR CATEGORÍA
    ============================================================
  */

  Future<void> _eliminarCategoria(
      Map<String, dynamic> categoria,
      ) async {
    if (_isProcessing) return;

    final id = int.tryParse(
      categoria['id'].toString(),
    );

    if (id == null) {
      _mostrarMensaje(
        'No se pudo identificar la categoría',
        isError: true,
      );
      return;
    }

    final nombre =
        categoria['nombre']?.toString() ??
            'esta categoría';

    final totalFaq = int.tryParse(
      categoria['total_faq']?.toString() ?? '0',
    ) ??
        0;

    /*
      Si ya sabemos que existen preguntas asociadas,
      evitamos hacer una petición innecesaria.

      El backend también lo valida.
    */
    if (totalFaq > 0) {
      _mostrarMensaje(
        'No se puede eliminar "$nombre" porque tiene '
            '$totalFaq ${totalFaq == 1 ? 'pregunta asociada' : 'preguntas asociadas'}.',
        isError: true,
      );

      return;
    }

    final confirmar =
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(20),
          ),
          title: const Text(
            'Eliminar categoría',
            style: TextStyle(
              color: darkText,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            '¿Deseas eliminar la categoría "$nombre"?\n\n'
                'Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Cancelar',
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                Colors.red.shade700,
                foregroundColor:
                Colors.white,
              ),
              icon: const Icon(
                Icons.delete_outline,
              ),
              label: const Text(
                'Eliminar',
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await _faqService.deleteCategory(
        id: id,
      );

      if (!mounted) return;

      _mostrarMensaje(
        'Categoría eliminada correctamente',
      );

      await _cargarCategorias();
    } on FaqException catch (e) {
      if (!mounted) return;

      _mostrarMensaje(
        e.message,
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje(
        'No se pudo eliminar la categoría',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
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
        backgroundColor: isError
            ? Colors.red.shade700
            : accentGreen,
      ),
    );
  }

  /*
    ============================================================
    INTERFAZ
    ============================================================
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: lightGreen,
        foregroundColor: darkText,
        elevation: 0,
        title: const Text(
          'Categorías FAQ',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed:
            _isLoading || _isProcessing
                ? null
                : _cargarCategorias,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      floatingActionButton:
      FloatingActionButton.extended(
        onPressed:
        _isProcessing
            ? null
            : _crearCategoria,
        backgroundColor: accentGreen,
        foregroundColor: Colors.white,
        icon: const Icon(
          Icons.add_rounded,
        ),
        label: const Text(
          'Nueva categoría',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargarCategorias,
          color: accentGreen,
          child: ListView(
            physics:
            const AlwaysScrollableScrollPhysics(),
            padding:
            const EdgeInsets.fromLTRB(
              16,
              18,
              16,
              100,
            ),
            children: [
              _buildHeader(),

              const SizedBox(height: 18),

              if (_isLoading)
                _buildLoading()
              else if (_errorMessage != null)
                _buildError()
              else if (_categorias.isEmpty)
                  _buildEmpty()
                else ...[
                    Text(
                      '${_categorias.length} '
                          '${_categorias.length == 1 ? 'categoría' : 'categorías'}',
                      style: const TextStyle(
                        color: darkText,
                        fontSize: 15,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 12),

                    ..._categorias.map(
                      _buildCategoryCard,
                    ),
                  ],
            ],
          ),
        ),
      ),
    );
  }

  /*
    ============================================================
    CABECERA
    ============================================================
  */

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: lightGreen,
        borderRadius:
        BorderRadius.circular(17),
      ),
      child: const Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.category_outlined,
            color: accentGreen,
            size: 30,
          ),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Organiza las preguntas',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 17,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Administra las categorías utilizadas '
                      'para organizar las preguntas frecuentes de AniMap.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /*
    ============================================================
    TARJETA DE CATEGORÍA
    ============================================================
  */

  Widget _buildCategoryCard(
      Map<String, dynamic> categoria,
      ) {
    final nombre =
        categoria['nombre']?.toString() ??
            'Sin nombre';

    final descripcion =
    categoria['descripcion']
        ?.toString()
        .trim()
        .isNotEmpty ==
        true
        ? categoria['descripcion'].toString()
        : 'Sin descripción';

    final totalFaq = int.tryParse(
      categoria['total_faq']?.toString() ?? '0',
    ) ??
        0;

    final totalActivas = int.tryParse(
      categoria['total_activas']?.toString() ?? '0',
    ) ??
        0;

    return Container(
      margin:
      const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(17),
        border: Border.all(
          color:
          accentGreen.withOpacity(0.14),
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius:
                  BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_outlined,
                  color: accentGreen,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  nombre,
                  style: const TextStyle(
                    color: darkText,
                    fontSize: 16,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                enabled: !_isProcessing,
                onSelected: (value) {
                  if (value == 'editar') {
                    _editarCategoria(
                      categoria,
                    );
                  }

                  if (value == 'eliminar') {
                    _eliminarCategoria(
                      categoria,
                    );
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'editar',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'eliminar',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Eliminar',
                          style: TextStyle(
                            color:
                            Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            descripcion,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 14),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCounter(
                Icons.help_outline_rounded,
                '$totalFaq ${totalFaq == 1 ? 'pregunta' : 'preguntas'}',
              ),
              _buildCounter(
                Icons.visibility_outlined,
                '$totalActivas activas',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCounter(
      IconData icon,
      String text,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: lightGreen,
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: accentGreen,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: accentGreen,
              fontSize: 11,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /*
    ============================================================
    CAMPOS
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
      border: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: accentGreen,
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Colors.redAccent,
        ),
      ),
    );
  }

  /*
    ============================================================
    ESTADOS DE LA PANTALLA
    ============================================================
  */

  Widget _buildLoading() {
    return const Padding(
      padding:
      EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: CircularProgressIndicator(
          color: accentGreen,
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage ??
                'Ocurrió un error',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: darkText,
              fontWeight:
              FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          ElevatedButton.icon(
            onPressed: _cargarCategorias,
            style:
            ElevatedButton.styleFrom(
              backgroundColor:
              accentGreen,
              foregroundColor:
              Colors.white,
            ),
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text(
              'Reintentar',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 45,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.category_outlined,
            size: 52,
            color: accentGreen,
          ),
          SizedBox(height: 14),
          Text(
            'No hay categorías FAQ',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkText,
              fontSize: 16,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Crea la primera categoría para comenzar a organizar las preguntas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}