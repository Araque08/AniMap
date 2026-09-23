import 'package:flutter/material.dart';

import '../../../data/faq/faq_service.dart';

class AdminFaqFormPage extends StatefulWidget {
  /// Si faq es null, la página funciona en modo CREAR.
  /// Si faq contiene información, funciona en modo EDITAR.
  final Map<String, dynamic>? faq;

  final FaqService? service;

  const AdminFaqFormPage({
    super.key,
    this.faq,
    this.service,
  });

  @override
  State<AdminFaqFormPage> createState() => _AdminFaqFormPageState();
}

class _AdminFaqFormPageState extends State<AdminFaqFormPage> {
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

  late final FaqService _service = widget.service ?? FaqService();

  // =========================================================
  // FORMULARIO
  // =========================================================

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _questionController;
  late final TextEditingController _answerController;

  List<Map<String, dynamic>> _categories = [];

  int? _selectedCategoryId;

  bool _active = true;
  bool _loading = true;
  bool _saving = false;

  String? _error;

  // =========================================================
  // MODO CREAR / EDITAR
  // =========================================================

  bool get _isEditing => widget.faq != null;

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _questionController = TextEditingController(
      text: widget.faq?['pregunta']?.toString() ?? '',
    );

    _answerController = TextEditingController(
      text: widget.faq?['respuesta']?.toString() ?? '',
    );

    _active = widget.faq == null
        ? true
        : widget.faq?['activa'] == true;

    _selectedCategoryId =
        (widget.faq?['fk_categoria'] as num?)?.toInt();

    _loadCategories();
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();

    super.dispose();
  }

  // =========================================================
  // CARGAR CATEGORÍAS
  // =========================================================

  Future<void> _loadCategories() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final categories = await _service.getCategories();

      if (!mounted) return;

      setState(() {
        _categories = categories;

        // Si estamos creando una pregunta y existen categorías,
        // seleccionamos la primera por defecto.
        if (!_isEditing &&
            _selectedCategoryId == null &&
            _categories.isNotEmpty) {
          _selectedCategoryId =
              (_categories.first['id'] as num).toInt();
        }

        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  // =========================================================
  // GUARDAR
  // =========================================================

  Future<void> _save() async {
    if (_saving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona una categoría para la pregunta.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _saving = true;
    });

    final input = {
      'categoriaId': _selectedCategoryId,
      'pregunta': _questionController.text.trim(),
      'respuesta': _answerController.text.trim(),
      'activa': _active,
    };

    try {
      // =====================================================
      // EDITAR
      // =====================================================

      if (_isEditing) {
        final id = (widget.faq!['id'] as num).toInt();

        await _service.updateFaq(
          id,
          input,
        );
      }

      // =====================================================
      // CREAR
      // =====================================================

      else {
        await _service.createFaq(
          input,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Pregunta actualizada correctamente'
                : 'Pregunta creada correctamente',
          ),
        ),
      );

      Navigator.pop(
        context,
        true,
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FaqException
                ? error.message
                : _isEditing
                ? 'No pudimos actualizar la pregunta. Intenta nuevamente.'
                : 'No pudimos crear la pregunta. Intenta nuevamente.',
          ),
        ),
      );
    }
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

      labelStyle: const TextStyle(
        color: textSecondary,
      ),

      hintStyle: const TextStyle(
        color: Color(0xFFA0AAA4),
        fontSize: 13,
      ),

      prefixIcon: Icon(
        icon,
        color: green,
      ),

      filled: true,

      fillColor: Colors.white,

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFDCE6E0),
        ),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFDCE6E0),
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: green,
          width: 1.6,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFB95050),
        ),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
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

        title: Text(
          _isEditing
              ? 'Editar pregunta'
              : 'Nueva pregunta',
          style: const TextStyle(
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
          : _buildForm(),
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
              'No pudimos cargar las categorías',
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
              onPressed: _loadCategories,
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
  // FORMULARIO
  // =========================================================

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        20,
        8,
        20,
        30,
      ),

      child: Form(
        key: _formKey,

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // =================================================
            // ENCABEZADO
            // =================================================

            Container(
              width: double.infinity,

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

              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,

                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: 0.16,
                      ),

                      borderRadius: BorderRadius.circular(
                        16,
                      ),
                    ),

                    child: Icon(
                      _isEditing
                          ? Icons.edit_note_rounded
                          : Icons.add_comment_outlined,

                      color: Colors.white,

                      size: 29,
                    ),
                  ),

                  const SizedBox(width: 16),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [
                        Text(
                          _isEditing
                              ? 'Editar pregunta frecuente'
                              : 'Crear pregunta frecuente',

                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          _isEditing
                              ? 'Modifica la información de esta pregunta del centro de ayuda.'
                              : 'Agrega una nueva pregunta y respuesta al centro de ayuda de AniMap.',

                          style: const TextStyle(
                            color: Color(0xFFE7F3EC),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 26),

            // =================================================
            // INFORMACIÓN
            // =================================================

            const Text(
              'Información de la pregunta',

              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              'Completa los campos para mostrar la información en el centro de ayuda.',

              style: TextStyle(
                color: textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // CATEGORÍA
            // =================================================

            const _FieldTitle(
              title: 'Categoría',
              requiredField: true,
            ),

            const SizedBox(height: 8),

            if (_categories.isEmpty)

            // =================================================
            // SIN CATEGORÍAS
            // =================================================

              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8EB),

                  borderRadius: BorderRadius.circular(
                    16,
                  ),

                  border: Border.all(
                    color: const Color(0xFFF0DEB7),
                  ),
                ),

                child: const Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFC28628),
                    ),

                    SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        'No hay categorías disponibles. Debes crear una categoría antes de registrar una pregunta frecuente.',

                        style: TextStyle(
                          color: Color(0xFF765A2C),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )

            else
              DropdownButtonFormField<int>(
                initialValue: _selectedCategoryId,

                isExpanded: true,

                decoration: _inputDecoration(
                  label: 'Seleccionar categoría',
                  hint: 'Selecciona una categoría',
                  icon: Icons.category_outlined,
                ),

                items: _categories.map(
                      (category) {
                    return DropdownMenuItem<int>(
                      value:
                      (category['id'] as num).toInt(),

                      child: Text(
                        category['nombre']
                            ?.toString() ??
                            'Categoría',

                        overflow:
                        TextOverflow.ellipsis,
                      ),
                    );
                  },
                ).toList(),

                onChanged: _saving
                    ? null
                    : (value) {
                  setState(() {
                    _selectedCategoryId = value;
                  });
                },

                validator: (value) {
                  if (value == null) {
                    return 'Selecciona una categoría';
                  }

                  return null;
                },
              ),

            const SizedBox(height: 22),

            // =================================================
            // PREGUNTA
            // =================================================

            const _FieldTitle(
              title: 'Pregunta',
              requiredField: true,
            ),

            const SizedBox(height: 8),

            TextFormField(
              controller: _questionController,

              enabled: !_saving,

              textCapitalization:
              TextCapitalization.sentences,

              textInputAction:
              TextInputAction.next,

              decoration: _inputDecoration(
                label: 'Pregunta',
                hint:
                'Ej. ¿Cómo puedo reportar una mascota perdida?',
                icon: Icons.help_outline_rounded,
              ),

              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Ingresa la pregunta';
                }

                return null;
              },
            ),

            const SizedBox(height: 22),

            // =================================================
            // RESPUESTA
            // =================================================

            const _FieldTitle(
              title: 'Respuesta',
              requiredField: true,
            ),

            const SizedBox(height: 8),

            TextFormField(
              controller: _answerController,

              enabled: !_saving,

              textCapitalization:
              TextCapitalization.sentences,

              minLines: 5,
              maxLines: 8,

              decoration: _inputDecoration(
                label: 'Respuesta',
                hint:
                'Escribe la respuesta que verá el usuario...',
                icon:
                Icons.chat_bubble_outline_rounded,
              ),

              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Ingresa la respuesta';
                }

                return null;
              },
            ),

            const SizedBox(height: 22),

            // =================================================
            // ESTADO
            // =================================================

            const _FieldTitle(
              title: 'Estado',
              requiredField: false,
            ),

            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(
                  17,
                ),

                border: Border.all(
                  color: const Color(0xFFDCE6E0),
                ),
              ),

              child: SwitchListTile(
                contentPadding:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 5,
                ),

                activeThumbColor: green,

                value: _active,

                onChanged: _saving
                    ? null
                    : (value) {
                  setState(() {
                    _active = value;
                  });
                },

                secondary: Container(
                  width: 42,
                  height: 42,

                  decoration: BoxDecoration(
                    color: _active
                        ? lightGreen
                        : const Color(0xFFF0F2F1),

                    borderRadius:
                    BorderRadius.circular(13),
                  ),

                  child: Icon(
                    _active
                        ? Icons.visibility_outlined
                        : Icons
                        .visibility_off_outlined,

                    color: _active
                        ? green
                        : const Color(0xFF87918C),

                    size: 21,
                  ),
                ),

                title: Text(
                  _active
                      ? 'Pregunta activa'
                      : 'Pregunta archivada',

                  style: const TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),

                subtitle: Text(
                  _active
                      ? 'Los usuarios podrán verla en el centro de ayuda.'
                      : 'La pregunta no será visible para los usuarios.',

                  style: const TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // =================================================
            // GUARDAR
            // =================================================

            SizedBox(
              width: double.infinity,

              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: green,

                  foregroundColor: Colors.white,

                  disabledBackgroundColor:
                  green.withValues(
                    alpha: 0.55,
                  ),

                  padding:
                  const EdgeInsets.symmetric(
                    vertical: 16,
                  ),

                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(16),
                  ),
                ),

                onPressed:
                _saving || _categories.isEmpty
                    ? null
                    : _save,

                icon: _saving
                    ? const SizedBox(
                  width: 19,
                  height: 19,

                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : Icon(
                  _isEditing
                      ? Icons.save_outlined
                      : Icons.add_rounded,
                ),

                label: Text(
                  _saving
                      ? 'Guardando...'
                      : _isEditing
                      ? 'Guardar cambios'
                      : 'Crear pregunta',

                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // =================================================
            // CANCELAR
            // =================================================

            SizedBox(
              width: double.infinity,

              child: TextButton(
                onPressed: _saving
                    ? null
                    : () {
                  Navigator.pop(context);
                },

                child: const Text(
                  'Cancelar',
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
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

// =============================================================
// TÍTULO DE CAMPO
// =============================================================

class _FieldTitle extends StatelessWidget {
  final String title;
  final bool requiredField;

  const _FieldTitle({
    required this.title,
    required this.requiredField,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,

          style: const TextStyle(
            color: _AdminFaqFormPageState.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),

        if (requiredField) ...[
          const SizedBox(width: 4),

          const Text(
            '*',

            style: TextStyle(
              color: Color(0xFFB95050),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}