import 'package:flutter/material.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../../admin/data/faq_service.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  // ============================================================
  // COLORES ANIMAP
  // ============================================================

  static const Color backgroundColor = Color(0xFFF7FAF7);
  static const Color lightGreen = Color(0xFFDFF3E8);
  static const Color darkText = Color(0xFF344955);
  static const Color accentGreen = Color(0xFF3F9568);
  static const Color secondaryText = Color(0xFF73828C);

  // ============================================================
  // SERVICIO
  // ============================================================

  final FaqService _faqService = FaqService();

  // ============================================================
  // BUSCADOR
  // ============================================================

  final TextEditingController _searchController =
  TextEditingController();

  // ============================================================
  // DATOS
  // ============================================================

  List<Map<String, dynamic>> _faqs = [];
  List<Map<String, dynamic>> _categorias = [];

  int? _categoriaSeleccionada;

  bool _isLoading = true;
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

  // ============================================================
  // CARGAR FAQ Y CATEGORÍAS
  // ============================================================

  Future<void> _cargarDatos() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      /*
        Las categorías se consultan desde PostgreSQL.

        Las FAQ públicas se consultan mediante GET /api/faqs.
        El backend ya se encarga de devolver únicamente
        las preguntas activas.
      */

      final resultados = await Future.wait([
        _faqService.getCategories(),
        _faqService.getPublicFaqs(
          categoriaId: _categoriaSeleccionada,
          search: _searchController.text.trim(),
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
        'No se pudieron cargar las preguntas frecuentes.';
      });
    }
  }

  // ============================================================
  // SELECCIONAR CATEGORÍA
  // ============================================================

  Future<void> _seleccionarCategoria(
      int? categoriaId,
      ) async {
    if (_categoriaSeleccionada == categoriaId) {
      return;
    }

    setState(() {
      _categoriaSeleccionada = categoriaId;
    });

    await _cargarDatos();
  }

  // ============================================================
  // BUSCAR
  // ============================================================

  Future<void> _buscar() async {
    FocusScope.of(context).unfocus();

    await _cargarDatos();
  }

  // ============================================================
  // LIMPIAR BÚSQUEDA
  // ============================================================

  Future<void> _limpiarBusqueda() async {
    _searchController.clear();

    setState(() {});

    await _cargarDatos();
  }

  // ============================================================
  // INTERFAZ
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,

      drawer: const AniMapSideMenu(),

      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            /*
              ==================================================
              MENÚ SUPERIOR ANIMAP
              ==================================================
            */

            const TopMenuAnimap(),

            /*
              ==================================================
              CABECERA
              ==================================================
            */

            _buildHeader(),

            /*
              ==================================================
              CONTENIDO
              ==================================================
            */

            Expanded(
              child: RefreshIndicator(
                color: accentGreen,
                onRefresh: _cargarDatos,
                child: ListView(
                  physics:
                  const AlwaysScrollableScrollPhysics(),
                  padding:
                  const EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    120,
                  ),
                  children: [
                    /*
                      ==========================================
                      BUSCADOR
                      ==========================================
                    */

                    _buildSearchField(),

                    const SizedBox(height: 16),

                    /*
                      ==========================================
                      TÍTULO CATEGORÍAS
                      ==========================================
                    */

                    const Text(
                      'Categorías',
                      style: TextStyle(
                        color: darkText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 10),

                    /*
                      ==========================================
                      CATEGORÍAS
                      ==========================================
                    */

                    _buildCategories(),

                    const SizedBox(height: 22),

                    /*
                      ==========================================
                      RESULTADOS
                      ==========================================
                    */

                    if (_isLoading)
                      _buildLoading()
                    else if (_errorMessage != null)
                      _buildError()
                    else if (_faqs.isEmpty)
                        _buildEmpty()
                      else ...[
                          _buildResultHeader(),

                          const SizedBox(height: 12),

                          ..._faqs.map(
                                (faq) => _buildFaqCard(faq),
                          ),
                        ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar:
      const BottomMenuAnimap(
        currentIndex: -1,
      ),
    );
  }

  // ============================================================
  // CABECERA
  // ============================================================

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.fromLTRB(
        20,
        10,
        20,
        18,
      ),
      decoration: const BoxDecoration(
        color: lightGreen,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      child: const Row(
        crossAxisAlignment:
        CrossAxisAlignment.center,
        children: [
          /*
            Icono
          */

          _FaqHeaderIcon(),

          SizedBox(width: 14),

          /*
            Texto
          */

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Centro de ayuda',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 24,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Encuentra respuestas rápidas sobre el uso de AniMap.',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 13.5,
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

  // ============================================================
  // BUSCADOR
  // ============================================================

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      textInputAction:
      TextInputAction.search,
      onSubmitted: (_) => _buscar(),
      onChanged: (_) {
        /*
          Actualizamos solamente para mostrar u ocultar
          el botón X del buscador.
        */
        setState(() {});
      },
      decoration: InputDecoration(
        hintText:
        'Buscar una pregunta...',
        hintStyle: const TextStyle(
          color: secondaryText,
          fontSize: 14,
        ),
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
          onPressed:
          _limpiarBusqueda,
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
          BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
        focusedBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(16),
          borderSide:
          const BorderSide(
            color: accentGreen,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CATEGORÍAS
  // ============================================================

  Widget _buildCategories() {
    /*
      Mientras se carga por primera vez mostramos un pequeño
      indicador en lugar de categorías falsas.
    */

    if (_isLoading &&
        _categorias.isEmpty) {
      return const SizedBox(
        height: 44,
        child: Align(
          alignment:
          Alignment.centerLeft,
          child: SizedBox(
            width: 22,
            height: 22,
            child:
            CircularProgressIndicator(
              strokeWidth: 2,
              color: accentGreen,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection:
        Axis.horizontal,
        itemCount:
        _categorias.length + 1,
        separatorBuilder: (_, __) =>
        const SizedBox(width: 8),
        itemBuilder: (
            context,
            index,
            ) {
          /*
            La primera opción siempre es TODAS.
          */

          if (index == 0) {
            final isSelected =
                _categoriaSeleccionada ==
                    null;

            return _buildCategoryChip(
              text: 'Todas',
              selected: isSelected,
              onSelected: () {
                _seleccionarCategoria(
                  null,
                );
              },
            );
          }

          final categoria =
          _categorias[index - 1];

          final id = int.tryParse(
            categoria['id'].toString(),
          );

          final nombre =
              categoria['nombre']
                  ?.toString() ??
                  'Sin nombre';

          final isSelected =
              _categoriaSeleccionada ==
                  id;

          return _buildCategoryChip(
            text: nombre,
            selected: isSelected,
            onSelected: () {
              if (id != null) {
                _seleccionarCategoria(
                  id,
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildCategoryChip({
    required String text,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(text),
      selected: selected,
      showCheckmark: false,
      selectedColor: accentGreen,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected
            ? accentGreen
            : const Color(0xFFD6E5DC),
      ),
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(22),
      ),
      labelStyle: TextStyle(
        color: selected
            ? Colors.white
            : accentGreen,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) {
        onSelected();
      },
    );
  }

  // ============================================================
  // ENCABEZADO DE RESULTADOS
  // ============================================================

  Widget _buildResultHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Preguntas frecuentes',
            style: TextStyle(
              color: darkText,
              fontSize: 17,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ),
        Container(
          padding:
          const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: lightGreen,
            borderRadius:
            BorderRadius.circular(20),
          ),
          child: Text(
            '${_faqs.length}',
            style: const TextStyle(
              color: accentGreen,
              fontSize: 12,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TARJETA FAQ
  // ============================================================

  Widget _buildFaqCard(
      Map<String, dynamic> faq,
      ) {
    final pregunta =
        faq['pregunta']
            ?.toString()
            .trim() ??
            '';

    final respuesta =
        faq['respuesta']
            ?.toString()
            .trim() ??
            '';

    final categoria =
        faq['categoria']
            ?.toString()
            .trim() ??
            'General';

    return Container(
      margin:
      const EdgeInsets.only(
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(17),
        border: Border.all(
          color:
          const Color(0xFFE6ECE8),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        /*
          Quitamos las líneas automáticas
          del ExpansionTile.
        */
        data: Theme.of(context)
            .copyWith(
          dividerColor:
          Colors.transparent,
        ),
        child: ExpansionTile(
          iconColor: accentGreen,
          collapsedIconColor:
          accentGreen,
          tilePadding:
          const EdgeInsets.fromLTRB(
            16,
            7,
            14,
            7,
          ),
          childrenPadding:
          const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            17,
          ),
          title: Text(
            pregunta.isEmpty
                ? 'Pregunta sin título'
                : pregunta,
            style: const TextStyle(
              fontWeight:
              FontWeight.w700,
              fontSize: 15,
              color: darkText,
              height: 1.3,
            ),
          ),
          subtitle: Padding(
            padding:
            const EdgeInsets.only(
              top: 6,
            ),
            child: Align(
              alignment:
              Alignment.centerLeft,
              child: Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration:
                BoxDecoration(
                  color: lightGreen,
                  borderRadius:
                  BorderRadius.circular(
                    15,
                  ),
                ),
                child: Text(
                  categoria,
                  style:
                  const TextStyle(
                    color:
                    accentGreen,
                    fontSize: 11,
                    fontWeight:
                    FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          children: [
            const Divider(
              color: Color(
                0xFFE8EEEA,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment:
              Alignment.centerLeft,
              child: Text(
                respuesta.isEmpty
                    ? 'Esta pregunta todavía no tiene una respuesta.'
                    : respuesta,
                style:
                const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color:
                  Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CARGANDO
  // ============================================================

  Widget _buildLoading() {
    return const Padding(
      padding:
      EdgeInsets.symmetric(
        vertical: 55,
      ),
      child: Column(
        children: [
          CircularProgressIndicator(
            color: accentGreen,
          ),
          SizedBox(height: 15),
          Text(
            'Cargando preguntas...',
            style: TextStyle(
              color: secondaryText,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  Widget _buildError() {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 35,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(17),
        border: Border.all(
          color:
          const Color(0xFFE6ECE8),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons
                .cloud_off_outlined,
            color:
            Colors.red.shade400,
            size: 48,
          ),
          const SizedBox(height: 14),
          const Text(
            'No pudimos cargar la ayuda',
            textAlign:
            TextAlign.center,
            style: TextStyle(
              color: darkText,
              fontSize: 16,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _errorMessage ??
                'Intenta nuevamente.',
            textAlign:
            TextAlign.center,
            style: const TextStyle(
              color: secondaryText,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _cargarDatos,
            style:
            ElevatedButton.styleFrom(
              backgroundColor:
              accentGreen,
              foregroundColor:
              Colors.white,
              elevation: 0,
              shape:
              RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(
                  14,
                ),
              ),
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

  // ============================================================
  // SIN RESULTADOS
  // ============================================================

  Widget _buildEmpty() {
    final tieneBusqueda =
        _searchController.text
            .trim()
            .isNotEmpty;

    final tieneCategoria =
        _categoriaSeleccionada !=
            null;

    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 25,
        vertical: 42,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(17),
        border: Border.all(
          color:
          const Color(0xFFE6ECE8),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              color: lightGreen,
              borderRadius:
              BorderRadius.circular(
                20,
              ),
            ),
            child: const Icon(
              Icons
                  .search_off_rounded,
              color: accentGreen,
              size: 33,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tieneBusqueda
                ? 'No se encontraron resultados para tu búsqueda.'
                : tieneCategoria
                ? 'No hay preguntas en esta categoría.'
                : 'No hay preguntas frecuentes registradas.',
            textAlign:
            TextAlign.center,
            style: const TextStyle(
              color: darkText,
              fontSize: 16,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            tieneBusqueda
                ? 'Prueba con otra palabra o borra la búsqueda.'
                : tieneCategoria
                ? 'Selecciona otra categoría o vuelve a Todas.'
                : 'Las preguntas de ayuda aparecerán aquí cuando estén disponibles.',
            textAlign:
            TextAlign.center,
            style: const TextStyle(
              color: secondaryText,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (tieneBusqueda ||
              tieneCategoria) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () async {
                _searchController.clear();

                setState(() {
                  _categoriaSeleccionada =
                  null;
                });

                await _cargarDatos();
              },
              style:
              OutlinedButton.styleFrom(
                foregroundColor:
                accentGreen,
                side: const BorderSide(
                  color: accentGreen,
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    14,
                  ),
                ),
              ),
              icon: const Icon(
                Icons
                    .restart_alt_rounded,
              ),
              label: const Text(
                'Ver todas',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================
// ICONO DE LA CABECERA
// =============================================================

class _FaqHeaderIcon extends StatelessWidget {
  const _FaqHeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
        BorderRadius.circular(15),
      ),
      child: const Icon(
        Icons.help_outline_rounded,
        color: _FaqScreenState.accentGreen,
        size: 28,
      ),
    );
  }
}
