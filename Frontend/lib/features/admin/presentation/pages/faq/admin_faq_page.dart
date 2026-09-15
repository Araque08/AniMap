import 'package:flutter/material.dart';

import '../../../data/faq_service.dart';
import 'admin_faq_form_page.dart';
import 'admin_faq_categories_page.dart';

class AdminFaqPage extends StatefulWidget {
  const AdminFaqPage({super.key});

  @override
  State<AdminFaqPage> createState() => _AdminFaqPageState();
}

class _AdminFaqPageState extends State<AdminFaqPage> {
  /*
    ============================================================
    COLORES DE ANIMAP
    ============================================================
  */

  static const Color lightGreen = Color(0xFFDFF3E8);
  static const Color darkText = Color(0xFF344955);
  static const Color accentGreen = Color(0xFF3F9568);
  static const Color backgroundColor = Color(0xFFF7FAF8);

  /*
    ============================================================
    SERVICIO
    ============================================================
  */

  final FaqService _faqService = FaqService();

  /*
    ============================================================
    CONTROLADORES
    ============================================================
  */

  final TextEditingController _searchController =
  TextEditingController();

  /*
    ============================================================
    ESTADO
    ============================================================
  */

  List<Map<String, dynamic>> _faqs = [];
  List<Map<String, dynamic>> _categorias = [];

  int? _categoriaSeleccionada;

  bool _isLoading = true;
  bool _isChangingStatus = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _cargarDatos();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  /*
    ============================================================
    CARGAR INFORMACIÓN
    ============================================================
  */

  Future<void> _cargarDatos() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final resultados = await Future.wait([
        _faqService.getCategories(),
        _faqService.getAdminFaqs(
          categoriaId: _categoriaSeleccionada,
          search: _searchController.text,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _categorias = resultados[0];
        _faqs = resultados[1];
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
        'Ocurrió un error al cargar las preguntas frecuentes';
      });
    }
  }

  /*
    ============================================================
    BUSCAR
    ============================================================
  */

  Future<void> _buscar() async {
    FocusScope.of(context).unfocus();

    await _cargarDatos();
  }

  /*
    ============================================================
    LIMPIAR FILTROS
    ============================================================
  */

  Future<void> _limpiarFiltros() async {
    _searchController.clear();

    setState(() {
      _categoriaSeleccionada = null;
    });

    await _cargarDatos();
  }

  /*
    ============================================================
    CAMBIAR ESTADO
    ============================================================
  */

  Future<void> _cambiarEstado(
      Map<String, dynamic> faq,
      ) async {
    if (_isChangingStatus) return;

    final id = int.tryParse(
      faq['id'].toString(),
    );

    if (id == null) {
      _mostrarMensaje(
        'No se pudo identificar la pregunta frecuente',
        isError: true,
      );

      return;
    }

    final bool activa =
        faq['activa'] == true;

    final accion =
    activa ? 'archivar' : 'activar';

    final confirmar =
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            activa
                ? 'Archivar pregunta'
                : 'Activar pregunta',
          ),
          content: Text(
            activa
                ? '¿Deseas archivar esta pregunta frecuente? '
                'Dejará de mostrarse en la sección pública.'
                : '¿Deseas activar esta pregunta frecuente? '
                'Volverá a mostrarse en la sección pública.',
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
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                activa
                    ? Colors.orange.shade700
                    : accentGreen,
                foregroundColor:
                Colors.white,
              ),
              child: Text(
                activa
                    ? 'Archivar'
                    : 'Activar',
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    setState(() {
      _isChangingStatus = true;
    });

    try {
      await _faqService.changeFaqStatus(
        id: id,
        activa: !activa,
      );

      if (!mounted) return;

      _mostrarMensaje(
        activa
            ? 'Pregunta archivada correctamente'
            : 'Pregunta activada correctamente',
      );

      await _cargarDatos();
    } on FaqException catch (e) {
      if (!mounted) return;

      _mostrarMensaje(
        e.message,
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje(
        'No se pudo cambiar el estado de la pregunta',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChangingStatus = false;
        });
      }
    }
  }

  /*
    ============================================================
    NAVEGACIÓN
    ============================================================

    Estas dos funciones las conectaremos con las pantallas
    que construiremos a continuación.
  */

  Future<void> _crearFaq() async {
    final resultado =
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
        const AdminFaqFormPage(),
      ),
    );

    if (resultado == true &&
        mounted) {
      await _cargarDatos();
    }
  }

  Future<void> _editarFaq(
      Map<String, dynamic> faq,
      ) async {
    final resultado =
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AdminFaqFormPage(
              faq: faq,
            ),
      ),
    );

    if (resultado == true &&
        mounted) {
      await _cargarDatos();
    }
  }

  Future<void> _administrarCategorias() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
        const AdminFaqCategoriesPage(),
      ),
    );

    if (!mounted) return;

    /*
    Cuando regresamos, actualizamos las categorías y las FAQ
    por si el administrador realizó algún cambio.
  */
    await _cargarDatos();
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
    INTERFAZ
    ============================================================
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,

      /*
        ========================================================
        ENCABEZADO
        ========================================================
      */

      appBar: AppBar(
        backgroundColor: lightGreen,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Preguntas frecuentes',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed:
            _isLoading
                ? null
                : _cargarDatos,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),

      /*
        ========================================================
        BOTÓN CREAR
        ========================================================
      */

      floatingActionButton:
      FloatingActionButton.extended(
        onPressed: _crearFaq,
        backgroundColor: accentGreen,
        foregroundColor: Colors.white,
        icon: const Icon(
          Icons.add_rounded,
        ),
        label: const Text(
          'Nueva pregunta',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            /*
              ==================================================
              CABECERA INFORMATIVA
              ==================================================
            */

            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.fromLTRB(
                20,
                18,
                20,
                18,
              ),
              color: lightGreen,
              child: const Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestión de FAQ',
                    style: TextStyle(
                      color: darkText,
                      fontSize: 22,
                      fontWeight:
                      FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Crea, edita, organiza y administra '
                        'las preguntas de ayuda de AniMap.',
                    style: TextStyle(
                      color: darkText,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            /*
              ==================================================
              CONTENIDO
              ==================================================
            */

            Expanded(
              child: RefreshIndicator(
                onRefresh: _cargarDatos,
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
                    /*
                      ==========================================
                      ADMINISTRAR CATEGORÍAS
                      ==========================================
                    */

                    _buildCategoriesButton(),

                    const SizedBox(height: 16),

                    /*
                      ==========================================
                      BUSCADOR
                      ==========================================
                    */

                    _buildSearchField(),

                    const SizedBox(height: 12),

                    /*
                      ==========================================
                      FILTRO CATEGORÍA
                      ==========================================
                    */

                    _buildCategoryFilter(),

                    const SizedBox(height: 10),

                    /*
                      ==========================================
                      LIMPIAR FILTROS
                      ==========================================
                    */

                    if (
                    _categoriaSeleccionada !=
                        null ||
                        _searchController
                            .text
                            .trim()
                            .isNotEmpty)
                      Align(
                        alignment:
                        Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed:
                          _limpiarFiltros,
                          icon: const Icon(
                            Icons
                                .filter_alt_off_outlined,
                          ),
                          label: const Text(
                            'Limpiar filtros',
                          ),
                        ),
                      ),

                    const SizedBox(height: 6),

                    /*
                      ==========================================
                      RESULTADOS
                      ==========================================
                    */

                    if (_isLoading)
                      _buildLoading()
                    else if (_errorMessage !=
                        null)
                      _buildError()
                    else if (_faqs.isEmpty)
                        _buildEmpty()
                      else ...[
                          _buildResultCount(),

                          const SizedBox(
                            height: 12,
                          ),

                          ..._faqs.map(
                                (faq) =>
                                _buildFaqCard(
                                  faq,
                                ),
                          ),
                        ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /*
    ============================================================
    BOTÓN CATEGORÍAS
    ============================================================
  */

  Widget _buildCategoriesButton() {
    return Material(
      color: Colors.white,
      borderRadius:
      BorderRadius.circular(16),
      child: InkWell(
        onTap: _administrarCategorias,
        borderRadius:
        BorderRadius.circular(16),
        child: Container(
          padding:
          const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          decoration: BoxDecoration(
            borderRadius:
            BorderRadius.circular(16),
            border: Border.all(
              color:
              accentGreen.withOpacity(
                0.18,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius:
                  BorderRadius.circular(
                    13,
                  ),
                ),
                child: const Icon(
                  Icons
                      .category_outlined,
                  color: accentGreen,
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
                        color: darkText,
                        fontSize: 16,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Crear, editar y eliminar categorías',
                      style: TextStyle(
                        color:
                        Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons
                    .arrow_forward_ios_rounded,
                size: 17,
                color: Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /*
    ============================================================
    BUSCADOR
    ============================================================
  */

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      textInputAction:
      TextInputAction.search,
      onSubmitted: (_) => _buscar(),
      onChanged: (_) {
        setState(() {});
      },
      decoration: InputDecoration(
        hintText:
        'Buscar pregunta o respuesta...',
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: accentGreen,
        ),
        suffixIcon:
        _searchController.text.isEmpty
            ? null
            : IconButton(
          tooltip:
          'Borrar búsqueda',
          onPressed: () async {
            _searchController
                .clear();

            setState(() {});

            await _cargarDatos();
          },
          icon: const Icon(
            Icons.close_rounded,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
        const EdgeInsets.symmetric(
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(15),
          borderSide: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(15),
          borderSide:
          const BorderSide(
            color: accentGreen,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  /*
    ============================================================
    FILTRO POR CATEGORÍA
    ============================================================
  */

  Widget _buildCategoryFilter() {
    return DropdownButtonFormField<int?>(
      value: _categoriaSeleccionada,
      decoration: InputDecoration(
        labelText: 'Categoría',
        prefixIcon: const Icon(
          Icons.filter_list_rounded,
          color: accentGreen,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(15),
          borderSide: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(15),
          borderSide:
          const BorderSide(
            color: accentGreen,
          ),
        ),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text(
            'Todas las categorías',
          ),
        ),
        ..._categorias.map(
              (categoria) {
            final id = int.tryParse(
              categoria['id'].toString(),
            );

            if (id == null) {
              return const DropdownMenuItem<
                  int?>(
                value: -1,
                child: Text(
                  'Categoría inválida',
                ),
              );
            }

            return DropdownMenuItem<int?>(
              value: id,
              child: Text(
                categoria['nombre']
                    ?.toString() ??
                    'Sin nombre',
              ),
            );
          },
        ),
      ],
      onChanged: _isLoading
          ? null
          : (value) async {
        setState(() {
          _categoriaSeleccionada =
              value;
        });

        await _cargarDatos();
      },
    );
  }

  /*
    ============================================================
    TOTAL RESULTADOS
    ============================================================
  */

  Widget _buildResultCount() {
    final activas = _faqs
        .where(
          (faq) =>
      faq['activa'] == true,
    )
        .length;

    final archivadas =
        _faqs.length - activas;

    return Row(
      children: [
        Expanded(
          child: Text(
            '${_faqs.length} '
                '${_faqs.length == 1 ? 'pregunta' : 'preguntas'}',
            style: const TextStyle(
              color: darkText,
              fontWeight:
              FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        Text(
          '$activas activas',
          style: const TextStyle(
            color: accentGreen,
            fontSize: 12,
            fontWeight:
            FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$archivadas archivadas',
          style: const TextStyle(
            color: Colors.black45,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /*
    ============================================================
    TARJETA FAQ
    ============================================================
  */

  Widget _buildFaqCard(
      Map<String, dynamic> faq,
      ) {
    final bool activa =
        faq['activa'] == true;

    final pregunta =
        faq['pregunta']
            ?.toString() ??
            'Sin pregunta';

    final respuesta =
        faq['respuesta']
            ?.toString() ??
            'Sin respuesta';

    final categoria =
        faq['categoria']
            ?.toString() ??
            'Sin categoría';

    return Container(
      margin:
      const EdgeInsets.only(
        bottom: 13,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(17),
        border: Border.all(
          color: activa
              ? accentGreen.withOpacity(
            0.15,
          )
              : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(
              0.035,
            ),
            blurRadius: 10,
            offset:
            const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            /*
              CATEGORÍA Y ESTADO
            */

            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildTag(
                        categoria,
                        lightGreen,
                        accentGreen,
                      ),
                      _buildTag(
                        activa
                            ? 'Activa'
                            : 'Archivada',
                        activa
                            ? const Color(
                          0xFFE7F6EC,
                        )
                            : const Color(
                          0xFFF1F1F1,
                        ),
                        activa
                            ? accentGreen
                            : Colors
                            .black54,
                      ),
                    ],
                  ),
                ),

                /*
                  MENÚ DE ACCIONES
                */

                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (value) {
                    if (value ==
                        'editar') {
                      _editarFaq(faq);
                    }

                    if (value ==
                        'estado') {
                      _cambiarEstado(
                        faq,
                      );
                    }
                  },
                  itemBuilder:
                      (context) => [
                    const PopupMenuItem(
                      value: 'editar',
                      child: Row(
                        children: [
                          Icon(
                            Icons
                                .edit_outlined,
                            size: 20,
                          ),
                          SizedBox(
                            width: 10,
                          ),
                          Text(
                            'Editar',
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'estado',
                      child: Row(
                        children: [
                          Icon(
                            activa
                                ? Icons
                                .archive_outlined
                                : Icons
                                .unarchive_outlined,
                            size: 20,
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Text(
                            activa
                                ? 'Archivar'
                                : 'Activar',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 13),

            /*
              PREGUNTA
            */

            Text(
              pregunta,
              style: const TextStyle(
                color: darkText,
                fontSize: 16,
                height: 1.3,
                fontWeight:
                FontWeight.w700,
              ),
            ),

            const SizedBox(height: 8),

            /*
              RESPUESTA
            */

            Text(
              respuesta,
              maxLines: 3,
              overflow:
              TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 14,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 14),

            /*
              BOTÓN EDITAR
            */

            Align(
              alignment:
              Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  _editarFaq(faq);
                },
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                ),
                label: const Text(
                  'Editar',
                ),
                style:
                TextButton.styleFrom(
                  foregroundColor:
                  accentGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /*
    ============================================================
    ETIQUETA
    ============================================================
  */

  Widget _buildTag(
      String text,
      Color background,
      Color foreground,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight:
          FontWeight.w700,
        ),
      ),
    );
  }

  /*
    ============================================================
    CARGANDO
    ============================================================
  */

  Widget _buildLoading() {
    return const Padding(
      padding:
      EdgeInsets.symmetric(
        vertical: 60,
      ),
      child: Center(
        child:
        CircularProgressIndicator(
          color: accentGreen,
        ),
      ),
    );
  }

  /*
    ============================================================
    ERROR
    ============================================================
  */

  Widget _buildError() {
    return Container(
      padding:
      const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons
                .error_outline_rounded,
            size: 45,
            color:
            Colors.red.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage ??
                'Ocurrió un error',
            textAlign:
            TextAlign.center,
            style: const TextStyle(
              color: darkText,
              fontWeight:
              FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _cargarDatos,
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

  /*
    ============================================================
    SIN RESULTADOS
    ============================================================
  */

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
            Icons
                .help_outline_rounded,
            size: 52,
            color: accentGreen,
          ),
          SizedBox(height: 14),
          Text(
            'No se encontraron preguntas frecuentes',
            textAlign:
            TextAlign.center,
            style: TextStyle(
              color: darkText,
              fontSize: 16,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Puedes crear una nueva pregunta o cambiar los filtros.',
            textAlign:
            TextAlign.center,
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