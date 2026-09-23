import 'package:flutter/material.dart';

import '../../../data/faq/faq_service.dart';

class AdminFaqCategoriesPage extends StatefulWidget {
  final FaqService? service;

  const AdminFaqCategoriesPage({
    super.key,
    this.service,
  });

  @override
  State<AdminFaqCategoriesPage> createState() =>
      _AdminFaqCategoriesPageState();
}

class _AdminFaqCategoriesPageState
    extends State<AdminFaqCategoriesPage> {
  // =========================================================
  // COLORES
  // =========================================================

  static const Color green = Color(0xFF3F9568);
  static const Color darkGreen = Color(0xFF2F7651);
  static const Color lightGreen = Color(0xFFEAF5EF);

  static const Color background = Color(0xFFF5F8F6);

  static const Color textPrimary = Color(0xFF26352E);
  static const Color textSecondary = Color(0xFF718078);

  // =========================================================
  // SERVICIO
  // =========================================================

  late final FaqService _service =
      widget.service ?? FaqService();

  // =========================================================
  // DATOS
  // =========================================================

  List<Map<String, dynamic>> _categories = [];

  bool _loading = true;

  String? _error;

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _load();
  }

  // =========================================================
  // CARGAR CATEGORÍAS
  // =========================================================

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final categories =
      await _service.getCategories();

      if (!mounted) return;

      setState(() {
        _categories = categories;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  // =========================================================
  // CREAR / EDITAR CATEGORÍA
  // =========================================================

  Future<void> _edit(
      Map<String, dynamic>? current,
      ) async {
    var name =
        current?['nombre']?.toString() ?? '';

    var description =
        current?['descripcion']?.toString() ?? '';

    final formKey =
    GlobalKey<FormState>();

    bool saving = false;

    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, update) {
            return PopScope(
              canPop: !saving,

              child: AlertDialog(
                backgroundColor: Colors.white,

                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(24),
                ),

                titlePadding:
                const EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  8,
                ),

                contentPadding:
                const EdgeInsets.fromLTRB(
                  24,
                  8,
                  24,
                  8,
                ),

                actionsPadding:
                const EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  18,
                ),

                // =============================================
                // TÍTULO
                // =============================================

                title: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,

                      decoration: BoxDecoration(
                        color: lightGreen,

                        borderRadius:
                        BorderRadius.circular(
                          14,
                        ),
                      ),

                      child: Icon(
                        current == null
                            ? Icons.add_rounded
                            : Icons.edit_outlined,

                        color: green,
                      ),
                    ),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [
                          Text(
                            current == null
                                ? 'Nueva categoría'
                                : 'Editar categoría',

                            style: const TextStyle(
                              color: textPrimary,
                              fontSize: 20,
                              fontWeight:
                              FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 3),

                          Text(
                            current == null
                                ? 'Organiza las preguntas del centro de ayuda.'
                                : 'Modifica la información de esta categoría.',

                            style: const TextStyle(
                              color: textSecondary,
                              fontSize: 12,
                              fontWeight:
                              FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // =============================================
                // FORMULARIO
                // =============================================

                content: SizedBox(
                  width: 420,

                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,

                      child: Column(
                        mainAxisSize:
                        MainAxisSize.min,

                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [
                          const SizedBox(height: 10),

                          // ===================================
                          // NOMBRE
                          // ===================================

                          const Text(
                            'Nombre *',

                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight:
                              FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: 8),

                          TextFormField(
                            initialValue: name,

                            enabled: !saving,

                            textCapitalization:
                            TextCapitalization
                                .sentences,

                            maxLength: 100,

                            decoration:
                            _inputDecoration(
                              label:
                              'Nombre de la categoría',

                              hint:
                              'Ej. Cuenta y acceso',

                              icon: Icons
                                  .category_outlined,
                            ),

                            onChanged: (value) {
                              name = value;
                            },

                            validator: (value) {
                              if (value == null ||
                                  value
                                      .trim()
                                      .isEmpty) {
                                return 'Ingresa el nombre';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 8),

                          // ===================================
                          // DESCRIPCIÓN
                          // ===================================

                          const Text(
                            'Descripción',

                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight:
                              FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: 8),

                          TextFormField(
                            initialValue:
                            description,

                            enabled: !saving,

                            textCapitalization:
                            TextCapitalization
                                .sentences,

                            minLines: 3,
                            maxLines: 4,

                            maxLength: 255,

                            decoration:
                            _inputDecoration(
                              label:
                              'Descripción opcional',

                              hint:
                              'Describe brevemente qué tipo de preguntas contiene.',

                              icon: Icons
                                  .notes_rounded,
                            ),

                            onChanged: (value) {
                              description = value;
                            },
                          ),

                          // ===================================
                          // ERROR
                          // ===================================

                          if (dialogError != null) ...[
                            const SizedBox(
                              height: 5,
                            ),

                            Container(
                              width: double.infinity,

                              padding:
                              const EdgeInsets.all(
                                12,
                              ),

                              decoration:
                              BoxDecoration(
                                color: const Color(
                                  0xFFFFEEEE,
                                ),

                                borderRadius:
                                BorderRadius.circular(
                                  12,
                                ),
                              ),

                              child: Row(
                                crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,

                                children: [
                                  const Icon(
                                    Icons
                                        .error_outline_rounded,

                                    color: Color(
                                      0xFFB95050,
                                    ),

                                    size: 19,
                                  ),

                                  const SizedBox(
                                    width: 8,
                                  ),

                                  Expanded(
                                    child: Text(
                                      dialogError!,

                                      style:
                                      const TextStyle(
                                        color: Color(
                                          0xFF9A4141,
                                        ),

                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // =============================================
                // BOTONES
                // =============================================

                actions: [
                  TextButton(
                    onPressed: saving
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

                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: green,

                      foregroundColor:
                      Colors.white,

                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),

                    onPressed: saving
                        ? null
                        : () async {
                      if (!formKey
                          .currentState!
                          .validate()) {
                        return;
                      }

                      update(() {
                        saving = true;
                        dialogError = null;
                      });

                      try {
                        // =================================
                        // CREAR
                        // =================================

                        if (current == null) {
                          await _service
                              .createCategory(
                            name.trim(),

                            description
                                .trim()
                                .isEmpty
                                ? null
                                : description
                                .trim(),
                          );
                        }

                        // =================================
                        // EDITAR
                        // =================================

                        else {
                          await _service
                              .updateCategory(
                            (current['id']
                            as num)
                                .toInt(),

                            name.trim(),

                            description
                                .trim()
                                .isEmpty
                                ? null
                                : description
                                .trim(),
                          );
                        }

                        if (!dialogContext
                            .mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                          true,
                        );
                      } catch (error) {
                        if (!dialogContext
                            .mounted) {
                          return;
                        }

                        update(() {
                          saving = false;

                          dialogError =
                          error
                          is FaqException
                              ? error.message
                              : 'No pudimos guardar la categoría. Intenta nuevamente.';
                        });
                      }
                    },

                    icon: saving
                        ? const SizedBox(
                      width: 17,
                      height: 17,

                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Icon(
                      current == null
                          ? Icons.add_rounded
                          : Icons
                          .save_outlined,
                    ),

                    label: Text(
                      saving
                          ? 'Guardando...'
                          : current == null
                          ? 'Crear'
                          : 'Guardar',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          current == null
              ? 'Categoría creada correctamente'
              : 'Categoría actualizada correctamente',
        ),
      ),
    );

    await _load();
  }

  // =========================================================
  // ELIMINAR CATEGORÍA
  // =========================================================

  Future<void> _delete(
      Map<String, dynamic> category,
      ) async {
    final totalFaq =
        (category['total_faq'] as num?)
            ?.toInt() ??
            0;

    // =======================================================
    // NO PERMITIR ELIMINAR SI TIENE FAQ
    // =======================================================

    if (totalFaq > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            totalFaq == 1
                ? 'Esta categoría tiene 1 pregunta asociada. Debes moverla o eliminarla primero.'
                : 'Esta categoría tiene $totalFaq preguntas asociadas. Debes moverlas o eliminarlas primero.',
          ),
        ),
      );

      return;
    }

    bool deleting = false;

    String? dialogError;

    final confirmed = await showDialog<bool>(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, update) {
            return PopScope(
              canPop: !deleting,

              child: AlertDialog(
                backgroundColor: Colors.white,

                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(24),
                ),

                title: Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,

                      decoration: BoxDecoration(
                        color:
                        const Color(0xFFFFEEEE),

                        borderRadius:
                        BorderRadius.circular(14),
                      ),

                      child: const Icon(
                        Icons.delete_outline_rounded,

                        color:
                        Color(0xFFB95050),
                      ),
                    ),

                    const SizedBox(width: 13),

                    const Expanded(
                      child: Text(
                        'Eliminar categoría',

                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 19,
                          fontWeight:
                          FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                content: Column(
                  mainAxisSize:
                  MainAxisSize.min,

                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    const Text(
                      '¿Seguro que deseas eliminar esta categoría?',

                      style: TextStyle(
                        color: textPrimary,
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,

                      padding:
                      const EdgeInsets.all(13),

                      decoration: BoxDecoration(
                        color:
                        const Color(0xFFF6F8F7),

                        borderRadius:
                        BorderRadius.circular(13),
                      ),

                      child: Row(
                        children: [
                          const Icon(
                            Icons
                                .category_outlined,

                            color: green,

                            size: 20,
                          ),

                          const SizedBox(width: 9),

                          Expanded(
                            child: Text(
                              category['nombre']
                                  ?.toString() ??
                                  'Categoría',

                              style:
                              const TextStyle(
                                color: textPrimary,

                                fontWeight:
                                FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Esta acción no se puede deshacer.',

                      style: TextStyle(
                        color:
                        Color(0xFFB95050),

                        fontSize: 12,

                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),

                    if (dialogError != null) ...[
                      const SizedBox(height: 12),

                      Text(
                        dialogError!,

                        style: const TextStyle(
                          color:
                          Color(0xFFB95050),

                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),

                actions: [
                  TextButton(
                    onPressed: deleting
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

                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                      const Color(0xFFB95050),

                      foregroundColor:
                      Colors.white,
                    ),

                    onPressed: deleting
                        ? null
                        : () async {
                      update(() {
                        deleting = true;
                        dialogError = null;
                      });

                      try {
                        await _service
                            .deleteCategory(
                          (category['id']
                          as num)
                              .toInt(),
                        );

                        if (!dialogContext
                            .mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                          true,
                        );
                      } catch (error) {
                        if (!dialogContext
                            .mounted) {
                          return;
                        }

                        update(() {
                          deleting = false;

                          dialogError =
                          error
                          is FaqException
                              ? error.message
                              : 'No pudimos eliminar la categoría. Intenta nuevamente.';
                        });
                      }
                    },

                    icon: deleting
                        ? const SizedBox(
                      width: 17,
                      height: 17,

                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(
                      Icons
                          .delete_outline_rounded,
                    ),

                    label: Text(
                      deleting
                          ? 'Eliminando...'
                          : 'Eliminar',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Categoría eliminada correctamente',
        ),
      ),
    );

    await _load();
  }

  // =========================================================
  // INPUT DECORATION
  // =========================================================

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,

      hintText: hint,

      prefixIcon: Icon(
        icon,
        color: green,
      ),

      filled: true,

      fillColor:
      const Color(0xFFF8FAF9),

      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),

      border: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(15),

        borderSide: const BorderSide(
          color: Color(0xFFDCE6E0),
        ),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(15),

        borderSide: const BorderSide(
          color: Color(0xFFDCE6E0),
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(15),

        borderSide: const BorderSide(
          color: green,
          width: 1.6,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(15),

        borderSide: const BorderSide(
          color: Color(0xFFB95050),
        ),
      ),

      focusedErrorBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(15),

        borderSide: const BorderSide(
          color: Color(0xFFB95050),
          width: 1.5,
        ),
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        backgroundColor: background,

        surfaceTintColor: background,

        elevation: 0,

        foregroundColor: textPrimary,

        title: const Text(
          'Categorías',

          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      body: _loading
          ? const Center(
        child:
        CircularProgressIndicator(
          color: green,
        ),
      )
          : _error != null
          ? _buildError()
          : RefreshIndicator(
        color: green,

        onRefresh: _load,

        child: _buildContent(),
      ),
    );
  }

  // =========================================================
  // ERROR
  // =========================================================

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            Container(
              width: 65,
              height: 65,

              decoration:
              const BoxDecoration(
                color: Color(0xFFFFEEEE),

                shape: BoxShape.circle,
              ),

              child: const Icon(
                Icons.error_outline_rounded,

                color: Color(0xFFB95050),

                size: 32,
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'No pudimos cargar las categorías',

              textAlign: TextAlign.center,

              style: TextStyle(
                color: textPrimary,

                fontSize: 18,

                fontWeight:
                FontWeight.w800,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              _error ?? '',

              textAlign: TextAlign.center,

              style: const TextStyle(
                color: textSecondary,
              ),
            ),

            const SizedBox(height: 18),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: green,

                foregroundColor:
                Colors.white,
              ),

              onPressed: _load,

              icon: const Icon(
                Icons.refresh_rounded,
              ),

              label: const Text(
                'Reintentar',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // CONTENIDO
  // =========================================================

  Widget _buildContent() {
    return ListView(
      physics:
      const AlwaysScrollableScrollPhysics(),

      padding: const EdgeInsets.fromLTRB(
        18,
        8,
        18,
        30,
      ),

      children: [
        // =====================================================
        // HEADER
        // =====================================================

        _buildHeader(),

        const SizedBox(height: 27),

        // =====================================================
        // TÍTULO
        // =====================================================

        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,

                children: [
                  Text(
                    'Categorías registradas',

                    style: TextStyle(
                      color: textPrimary,

                      fontSize: 19,

                      fontWeight:
                      FontWeight.w800,
                    ),
                  ),

                  SizedBox(height: 4),

                  Text(
                    'Organiza las preguntas frecuentes por tema.',

                    style: TextStyle(
                      color: textSecondary,

                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 7,
              ),

              decoration: BoxDecoration(
                color: lightGreen,

                borderRadius:
                BorderRadius.circular(20),
              ),

              child: Text(
                '${_categories.length}',

                style: const TextStyle(
                  color: darkGreen,

                  fontSize: 12,

                  fontWeight:
                  FontWeight.w800,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // =====================================================
        // LISTADO / VACÍO
        // =====================================================

        if (_categories.isEmpty)
          _buildEmptyState()
        else
          ..._categories.map(
                (category) {
              return Padding(
                padding:
                const EdgeInsets.only(
                  bottom: 13,
                ),

                child: _buildCategoryCard(
                  category,
                ),
              );
            },
          ),
      ],
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            green,
            darkGreen,
          ],

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,
        ),

        borderRadius:
        BorderRadius.circular(24),

        boxShadow: [
          BoxShadow(
            color: green.withValues(
              alpha: 0.18,
            ),

            blurRadius: 18,

            offset:
            const Offset(0, 7),
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
                width: 50,
                height: 50,

                decoration: BoxDecoration(
                  color: Colors.white
                      .withValues(
                    alpha: 0.16,
                  ),

                  borderRadius:
                  BorderRadius.circular(
                    16,
                  ),
                ),

                child: const Icon(
                  Icons.category_outlined,

                  color: Colors.white,

                  size: 28,
                ),
              ),

              const SizedBox(width: 14),

              const Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      'Categorías FAQ',

                      style: TextStyle(
                        color: Colors.white,

                        fontSize: 20,

                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),

                    SizedBox(height: 4),

                    Text(
                      'Agrupa las preguntas para que el centro de ayuda sea más fácil de consultar.',

                      style: TextStyle(
                        color:
                        Color(0xFFE7F3EC),

                        fontSize: 13,

                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ===================================================
          // NUEVA CATEGORÍA
          // ===================================================

          SizedBox(
            width: double.infinity,

            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                Colors.white,

                foregroundColor:
                darkGreen,

                padding:
                const EdgeInsets.symmetric(
                  vertical: 14,
                ),

                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    14,
                  ),
                ),
              ),

              onPressed: () {
                _edit(null);
              },

              icon: const Icon(
                Icons.add_rounded,
              ),

              label: const Text(
                'Nueva categoría',

                style: TextStyle(
                  fontWeight:
                  FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ESTADO VACÍO
  // =========================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,

      padding:
      const EdgeInsets.symmetric(
        horizontal: 25,
        vertical: 38,
      ),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
        BorderRadius.circular(21),

        border: Border.all(
          color: const Color(0xFFE3EAE6),
        ),
      ),

      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,

            decoration:
            const BoxDecoration(
              color: lightGreen,

              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.category_outlined,

              color: green,

              size: 31,
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'Aún no hay categorías',

            textAlign: TextAlign.center,

            style: TextStyle(
              color: textPrimary,

              fontSize: 17,

              fontWeight:
              FontWeight.w800,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'Crea una categoría para comenzar a organizar las preguntas frecuentes.',

            textAlign: TextAlign.center,

            style: TextStyle(
              color: textSecondary,

              fontSize: 13,

              height: 1.4,
            ),
          ),

          const SizedBox(height: 17),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: green,

              foregroundColor:
              Colors.white,
            ),

            onPressed: () {
              _edit(null);
            },

            icon: const Icon(
              Icons.add_rounded,
            ),

            label: const Text(
              'Crear categoría',
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // TARJETA DE CATEGORÍA
  // =========================================================

  Widget _buildCategoryCard(
      Map<String, dynamic> category,
      ) {
    final name =
        category['nombre']?.toString() ??
            'Categoría';

    final description =
        category['descripcion']
            ?.toString()
            .trim() ??
            '';

    final totalFaq =
        (category['total_faq'] as num?)
            ?.toInt() ??
            0;

    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
        BorderRadius.circular(20),

        border: Border.all(
          color: const Color(0xFFE2EAE5),
        ),
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          // ===================================================
          // ICONO
          // ===================================================

          Container(
            width: 50,
            height: 50,

            decoration: BoxDecoration(
              color: lightGreen,

              borderRadius:
              BorderRadius.circular(15),
            ),

            child: const Icon(
              Icons.folder_outlined,

              color: green,

              size: 25,
            ),
          ),

          const SizedBox(width: 14),

          // ===================================================
          // INFORMACIÓN
          // ===================================================

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  name,

                  style: const TextStyle(
                    color: textPrimary,

                    fontSize: 16,

                    fontWeight:
                    FontWeight.w800,
                  ),
                ),

                if (description.isNotEmpty) ...[
                  const SizedBox(height: 5),

                  Text(
                    description,

                    maxLines: 2,

                    overflow:
                    TextOverflow.ellipsis,

                    style: const TextStyle(
                      color: textSecondary,

                      fontSize: 12,

                      height: 1.4,
                    ),
                  ),
                ],

                const SizedBox(height: 9),

                // =============================================
                // CANTIDAD DE FAQ
                // =============================================

                Container(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),

                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFF2F6F4,
                    ),

                    borderRadius:
                    BorderRadius.circular(
                      20,
                    ),
                  ),

                  child: Row(
                    mainAxisSize:
                    MainAxisSize.min,

                    children: [
                      const Icon(
                        Icons
                            .help_outline_rounded,

                        color: textSecondary,

                        size: 14,
                      ),

                      const SizedBox(width: 5),

                      Text(
                        totalFaq == 1
                            ? '1 pregunta'
                            : '$totalFaq preguntas',

                        style:
                        const TextStyle(
                          color:
                          textSecondary,

                          fontSize: 11,

                          fontWeight:
                          FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 5),

          // ===================================================
          // MENÚ DE ACCIONES
          // ===================================================

          PopupMenuButton<String>(
            tooltip: 'Opciones',

            color: Colors.white,

            shape: RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(15),
            ),

            onSelected: (value) {
              if (value == 'edit') {
                _edit(category);
              }

              if (value == 'delete') {
                _delete(category);
              }
            },

            itemBuilder: (context) {
              return [
                const PopupMenuItem(
                  value: 'edit',

                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,

                        color: textSecondary,

                        size: 20,
                      ),

                      SizedBox(width: 10),

                      Text(
                        'Editar',
                      ),
                    ],
                  ),
                ),

                const PopupMenuItem(
                  value: 'delete',

                  child: Row(
                    children: [
                      Icon(
                        Icons
                            .delete_outline_rounded,

                        color:
                        Color(0xFFB95050),

                        size: 20,
                      ),

                      SizedBox(width: 10),

                      Text(
                        'Eliminar',

                        style: TextStyle(
                          color:
                          Color(0xFFB95050),
                        ),
                      ),
                    ],
                  ),
                ),
              ];
            },

            icon: const Icon(
              Icons.more_vert_rounded,

              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
