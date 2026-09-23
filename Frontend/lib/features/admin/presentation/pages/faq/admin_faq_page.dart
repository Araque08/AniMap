import 'package:flutter/material.dart';

import '../../../data/faq/faq_service.dart';
import 'admin_faq_categories_page.dart';
import 'admin_faq_form_page.dart';

class AdminFaqPage extends StatefulWidget {
  final FaqService? service;

  const AdminFaqPage({
    super.key,
    this.service,
  });

  @override
  State<AdminFaqPage> createState() => _AdminFaqPageState();
}

class _AdminFaqPageState extends State<AdminFaqPage> {
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

  List<Map<String, dynamic>> _faqs = [];
  List<Map<String, dynamic>> _categories = [];

  bool _loading = true;

  String? _error;

  // =========================================================
  // BUSCADOR Y FILTROS
  // =========================================================

  final TextEditingController _searchController =
  TextEditingController();

  String _searchText = '';

  int? _selectedCategoryId;

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _load();
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  // =========================================================
  // CARGAR FAQ Y CATEGORÍAS
  // =========================================================

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.getAdminFaqs(),
        _service.getCategories(),
      ]);

      if (!mounted) return;

      setState(() {
        _faqs = results[0];
        _categories = results[1];

        // Si una categoría fue eliminada desde la
        // administración de categorías, quitamos el filtro.
        if (_selectedCategoryId != null) {
          final categoryExists = _categories.any(
                (category) {
              final id =
              (category['id'] as num?)?.toInt();

              return id == _selectedCategoryId;
            },
          );

          if (!categoryExists) {
            _selectedCategoryId = null;
          }
        }

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
  // FAQ FILTRADAS
  // =========================================================

  List<Map<String, dynamic>> get _filteredFaqs {
    final search =
    _searchText.trim().toLowerCase();

    return _faqs.where((faq) {
      final question =
          faq['pregunta']
              ?.toString()
              .toLowerCase() ??
              '';

      final answer =
          faq['respuesta']
              ?.toString()
              .toLowerCase() ??
              '';

      final category =
          faq['categoria']
              ?.toString()
              .toLowerCase() ??
              '';

      // =====================================================
      // FILTRO POR TEXTO
      // =====================================================

      final matchesSearch =
          search.isEmpty ||
              question.contains(search) ||
              answer.contains(search) ||
              category.contains(search);

      // =====================================================
      // FILTRO POR CATEGORÍA
      // =====================================================

      bool matchesCategory = true;

      if (_selectedCategoryId != null) {
        final faqCategoryId =
        (faq['fk_categoria'] as num?)?.toInt();

        matchesCategory =
            faqCategoryId == _selectedCategoryId;
      }

      return matchesSearch && matchesCategory;
    }).toList();
  }

  // =========================================================
  // ABRIR FORMULARIO PARA CREAR
  // =========================================================

  Future<void> _createFaq() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminFaqFormPage(
          service: _service,
        ),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      await _load();
    }
  }

  // =========================================================
  // ABRIR FORMULARIO PARA EDITAR
  // =========================================================

  Future<void> _editFaq(
      Map<String, dynamic> faq,
      ) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminFaqFormPage(
          faq: faq,
          service: _service,
        ),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      await _load();
    }
  }

  // =========================================================
  // ABRIR CATEGORÍAS
  // =========================================================

  Future<void> _openCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
        const AdminFaqCategoriesPage(),
      ),
    );

    if (!mounted) return;

    // Al volver recargamos por si se creó,
    // modificó o eliminó alguna categoría.
    await _load();
  }

  // =========================================================
  // ACTIVAR / ARCHIVAR
  // =========================================================

  Future<void> _toggleFaq(
      Map<String, dynamic> faq,
      ) async {
    try {
      final currentlyActive =
          faq['activa'] == true;

      await _service.setFaqStatus(
        (faq['id'] as num).toInt(),
        !currentlyActive,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyActive
                ? 'Pregunta archivada correctamente'
                : 'Pregunta activada correctamente',
          ),
        ),
      );

      await _load();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FaqException
                ? error.message
                : 'No pudimos cambiar el estado de la pregunta.',
          ),
        ),
      );
    }
  }

  // =========================================================
  // ELIMINAR FAQ
  // =========================================================

  Future<void> _deleteFaq(
      Map<String, dynamic> faq,
      ) async {
    final id =
    (faq['id'] as num).toInt();

    final question =
        faq['pregunta']?.toString() ?? '';

    var deleting = false;

    String? dialogError;

    final deleted = await showDialog<bool>(
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
                        color: Color(0xFFB95050),
                      ),
                    ),

                    const SizedBox(width: 13),

                    const Expanded(
                      child: Text(
                        'Eliminar pregunta',
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '¿Seguro que deseas eliminar esta pregunta frecuente?',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    if (question.isNotEmpty) ...[
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

                        child: Text(
                          question,

                          maxLines: 3,

                          overflow:
                          TextOverflow.ellipsis,

                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    const Text(
                      'Esta acción no se puede deshacer.',
                      style: TextStyle(
                        color: Color(0xFFB95050),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    if (dialogError != null) ...[
                      const SizedBox(height: 12),

                      Text(
                        dialogError!,

                        style: const TextStyle(
                          color: Color(0xFFB95050),
                          fontSize: 13,
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

                      foregroundColor: Colors.white,
                    ),

                    onPressed: deleting
                        ? null
                        : () async {
                      update(() {
                        deleting = true;
                        dialogError = null;
                      });

                      try {
                        await _service.deleteFaq(
                          id,
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
                              : 'No pudimos eliminar la pregunta. Intenta nuevamente.';
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
                      Icons.delete_outline,
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

    if (deleted != true || !mounted) {
      return;
    }

    setState(() {
      _faqs.removeWhere(
            (item) => item['id'] == id,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pregunta frecuente eliminada correctamente',
        ),
      ),
    );
  }

  // =========================================================
  // LIMPIAR FILTROS
  // =========================================================

  void _clearFilters() {
    _searchController.clear();

    setState(() {
      _searchText = '';
      _selectedCategoryId = null;
    });
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
          'Preguntas frecuentes',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      body: _loading
          ? const Center(
        child: CircularProgressIndicator(
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

              decoration: const BoxDecoration(
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
              'No pudimos cargar las preguntas',
              textAlign: TextAlign.center,

              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
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
                foregroundColor: Colors.white,
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
    final filteredFaqs = _filteredFaqs;

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
        // ENCABEZADO
        // =====================================================

        _buildHeader(),

        const SizedBox(height: 26),

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
                    'Preguntas registradas',

                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  SizedBox(height: 4),

                  Text(
                    'Busca o filtra el contenido del centro de ayuda.',

                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 7,
              ),

              decoration: BoxDecoration(
                color: lightGreen,

                borderRadius:
                BorderRadius.circular(20),
              ),

              child: Text(
                '${filteredFaqs.length}/${_faqs.length}',

                style: const TextStyle(
                  color: darkGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // =====================================================
        // BUSCADOR
        // =====================================================

        _buildSearchField(),

        const SizedBox(height: 14),

        // =====================================================
        // FILTROS
        // =====================================================

        _buildCategoryFilters(),

        const SizedBox(height: 22),

        // =====================================================
        // RESULTADOS
        // =====================================================

        if (filteredFaqs.isEmpty)
          _buildEmptyState()
        else
          ...filteredFaqs.map(
                (faq) {
              return Padding(
                padding:
                const EdgeInsets.only(
                  bottom: 14,
                ),

                child: _buildFaqCard(
                  faq,
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

        borderRadius: BorderRadius.circular(24),

        boxShadow: [
          BoxShadow(
            color: green.withValues(
              alpha: 0.18,
            ),

            blurRadius: 18,

            offset: const Offset(
              0,
              7,
            ),
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
                width: 49,
                height: 49,

                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: 0.16,
                  ),

                  borderRadius:
                  BorderRadius.circular(15),
                ),

                child: const Icon(
                  Icons.help_center_outlined,
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
                      'Centro de ayuda',

                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),

                    SizedBox(height: 4),

                    Text(
                      'Administra las preguntas y categorías de AniMap.',

                      style: TextStyle(
                        color: Color(0xFFE7F3EC),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ===================================================
          // BOTONES
          // ===================================================

          Row(
            children: [
              // =================================================
              // NUEVA PREGUNTA
              // =================================================

              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,

                    foregroundColor: darkGreen,

                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 14,
                    ),

                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                    ),
                  ),

                  onPressed: _createFaq,

                  icon: const Icon(
                    Icons.add_rounded,
                  ),

                  label: const Text(
                    'Nueva pregunta',

                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // =================================================
              // CATEGORÍAS
              // =================================================

              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,

                    side: BorderSide(
                      color: Colors.white.withValues(
                        alpha: 0.55,
                      ),
                    ),

                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 14,
                    ),

                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                    ),
                  ),

                  onPressed: _openCategories,

                  icon: const Icon(
                    Icons.category_outlined,
                  ),

                  label: const Text(
                    'Categorías',

                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================
  // BUSCADOR
  // =========================================================

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,

      onChanged: (value) {
        setState(() {
          _searchText = value;
        });
      },

      decoration: InputDecoration(
        hintText:
        'Buscar pregunta, respuesta o categoría...',

        hintStyle: const TextStyle(
          color: Color(0xFF9AA69F),
          fontSize: 14,
        ),

        prefixIcon: const Icon(
          Icons.search_rounded,
          color: green,
        ),

        suffixIcon: _searchText.isNotEmpty
            ? IconButton(
          tooltip: 'Limpiar búsqueda',

          onPressed: () {
            _searchController.clear();

            setState(() {
              _searchText = '';
            });
          },

          icon: const Icon(
            Icons.close_rounded,
          ),
        )
            : null,

        filled: true,

        fillColor: Colors.white,

        contentPadding:
        const EdgeInsets.symmetric(
          vertical: 15,
        ),

        border: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(17),

          borderSide: BorderSide.none,
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(17),

          borderSide: const BorderSide(
            color: Color(0xFFE1E9E4),
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(17),

          borderSide: const BorderSide(
            color: green,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // FILTROS DE CATEGORÍAS
  // =========================================================

  Widget _buildCategoryFilters() {
    return SizedBox(
      height: 42,

      child: ListView(
        scrollDirection: Axis.horizontal,

        children: [
          _CategoryFilterChip(
            label: 'Todas',

            selected:
            _selectedCategoryId == null,

            onTap: () {
              setState(() {
                _selectedCategoryId = null;
              });
            },
          ),

          ..._categories.map(
                (category) {
              final id =
              (category['id'] as num).toInt();

              return _CategoryFilterChip(
                label:
                category['nombre']
                    ?.toString() ??
                    'Categoría',

                selected:
                _selectedCategoryId == id,

                onTap: () {
                  setState(() {
                    _selectedCategoryId = id;
                  });
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // =========================================================
  // SIN RESULTADOS
  // =========================================================

  Widget _buildEmptyState() {
    final filtering =
        _searchText.trim().isNotEmpty ||
            _selectedCategoryId != null;

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(
        horizontal: 25,
        vertical: 38,
      ),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(21),

        border: Border.all(
          color: const Color(0xFFE3EAE6),
        ),
      ),

      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,

            decoration: const BoxDecoration(
              color: lightGreen,
              shape: BoxShape.circle,
            ),

            child: Icon(
              filtering
                  ? Icons.search_off_rounded
                  : Icons.help_outline_rounded,

              color: green,

              size: 31,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            filtering
                ? 'No encontramos coincidencias'
                : 'Aún no hay preguntas',

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            filtering
                ? 'Prueba con otro texto o selecciona otra categoría.'
                : 'Crea la primera pregunta frecuente para el centro de ayuda.',

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),

          if (filtering) ...[
            const SizedBox(height: 16),

            TextButton.icon(
              onPressed: _clearFilters,

              icon: const Icon(
                Icons.filter_alt_off_outlined,
              ),

              label: const Text(
                'Limpiar filtros',
              ),
            ),
          ],

          if (!filtering) ...[
            const SizedBox(height: 16),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.white,
              ),

              onPressed: _createFaq,

              icon: const Icon(
                Icons.add_rounded,
              ),

              label: const Text(
                'Crear pregunta',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================
  // TARJETA FAQ
  // =========================================================

  Widget _buildFaqCard(
      Map<String, dynamic> faq,
      ) {
    final active =
        faq['activa'] == true;

    final question =
        faq['pregunta']?.toString() ?? '';

    final answer =
        faq['respuesta']?.toString() ?? '';

    final category =
        faq['categoria']?.toString() ??
            'Sin categoría';

    return Container(
      decoration: BoxDecoration(
        color: active
            ? Colors.white
            : const Color(0xFFF0F3F1),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(
          color: active
              ? const Color(0xFFE2EAE5)
              : const Color(0xFFD9DFDC),
        ),
      ),

      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),

        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,

            children: [
              // =================================================
              // INDICADOR
              // =================================================

              Container(
                width: 5,

                color: active
                    ? green
                    : const Color(0xFF9CA8A1),
              ),

              // =================================================
              // CONTENIDO
              // =================================================

              Expanded(
                child: Padding(
                  padding:
                  const EdgeInsets.fromLTRB(
                    16,
                    16,
                    10,
                    12,
                  ),

                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,

                    children: [
                      // =========================================
                      // CATEGORÍA Y ESTADO
                      // =========================================

                      Wrap(
                        spacing: 8,
                        runSpacing: 7,

                        children: [
                          // CATEGORÍA
                          Container(
                            padding:
                            const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),

                            decoration: BoxDecoration(
                              color: active
                                  ? lightGreen
                                  : const Color(
                                0xFFE1E5E3,
                              ),

                              borderRadius:
                              BorderRadius.circular(
                                20,
                              ),
                            ),

                            child: Text(
                              category,

                              style: TextStyle(
                                color: active
                                    ? darkGreen
                                    : const Color(
                                  0xFF68726D,
                                ),

                                fontSize: 11,

                                fontWeight:
                                FontWeight.w700,
                              ),
                            ),
                          ),

                          // ESTADO
                          Container(
                            padding:
                            const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),

                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(
                                0xFFE8F5EC,
                              )
                                  : const Color(
                                0xFFE2E6E4,
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
                                Container(
                                  width: 6,
                                  height: 6,

                                  decoration:
                                  BoxDecoration(
                                    color: active
                                        ? green
                                        : const Color(
                                      0xFF89958E,
                                    ),

                                    shape:
                                    BoxShape.circle,
                                  ),
                                ),

                                const SizedBox(width: 5),

                                Text(
                                  active
                                      ? 'Activa'
                                      : 'Archivada',

                                  style: TextStyle(
                                    color: active
                                        ? darkGreen
                                        : const Color(
                                      0xFF68726D,
                                    ),

                                    fontSize: 10,

                                    fontWeight:
                                    FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 13),

                      // =========================================
                      // PREGUNTA
                      // =========================================

                      Text(
                        question,

                        style: TextStyle(
                          color: active
                              ? textPrimary
                              : const Color(
                            0xFF5F6964,
                          ),

                          fontSize: 16,

                          fontWeight:
                          FontWeight.w800,

                          height: 1.3,
                        ),
                      ),

                      // =========================================
                      // RESPUESTA
                      // =========================================

                      if (answer.isNotEmpty) ...[
                        const SizedBox(height: 8),

                        Text(
                          answer,

                          maxLines: 3,

                          overflow:
                          TextOverflow.ellipsis,

                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],

                      const SizedBox(height: 11),

                      // =========================================
                      // ACCIONES
                      // =========================================

                      Row(
                        mainAxisAlignment:
                        MainAxisAlignment.end,

                        children: [
                          // EDITAR
                          _FaqActionButton(
                            tooltip:
                            'Editar pregunta',

                            icon:
                            Icons.edit_outlined,

                            color: const Color(
                              0xFF567267,
                            ),

                            onPressed: () {
                              _editFaq(faq);
                            },
                          ),

                          // ACTIVAR / ARCHIVAR
                          _FaqActionButton(
                            tooltip: active
                                ? 'Archivar pregunta'
                                : 'Activar pregunta',

                            icon: active
                                ? Icons
                                .visibility_off_outlined
                                : Icons
                                .visibility_outlined,

                            color: active
                                ? const Color(
                              0xFF7B8580,
                            )
                                : green,

                            onPressed: () {
                              _toggleFaq(faq);
                            },
                          ),

                          // ELIMINAR
                          _FaqActionButton(
                            tooltip:
                            'Eliminar pregunta',

                            icon: Icons
                                .delete_outline_rounded,

                            color: const Color(
                              0xFFB95050,
                            ),

                            onPressed: () {
                              _deleteFaq(faq);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// CHIP PARA FILTRAR CATEGORÍAS
// =============================================================

class _CategoryFilterChip extends StatelessWidget {
  final String label;

  final bool selected;

  final VoidCallback onTap;

  const _CategoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        right: 9,
      ),

      child: Material(
        color: selected
            ? _AdminFaqPageState.green
            : Colors.white,

        borderRadius: BorderRadius.circular(
          30,
        ),

        child: InkWell(
          borderRadius:
          BorderRadius.circular(30),

          onTap: onTap,

          child: Container(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),

            decoration: BoxDecoration(
              borderRadius:
              BorderRadius.circular(30),

              border: Border.all(
                color: selected
                    ? _AdminFaqPageState.green
                    : const Color(
                  0xFFDDE6E1,
                ),
              ),
            ),

            child: Text(
              label,

              style: TextStyle(
                color: selected
                    ? Colors.white
                    : _AdminFaqPageState
                    .textSecondary,

                fontSize: 12,

                fontWeight:
                FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// BOTONES EDITAR / ARCHIVAR / ELIMINAR
// =============================================================

class _FaqActionButton extends StatelessWidget {
  final String tooltip;

  final IconData icon;

  final Color color;

  final VoidCallback onPressed;

  const _FaqActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,

      visualDensity: VisualDensity.compact,

      onPressed: onPressed,

      icon: Icon(
        icon,
        color: color,
        size: 21,
      ),
    );
  }
}
