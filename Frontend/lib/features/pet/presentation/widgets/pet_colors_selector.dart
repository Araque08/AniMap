
import 'package:flutter/material.dart';

class PetColorsSelector extends StatefulWidget {
  final List<String> selectedColors;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  const PetColorsSelector({
    super.key,
    required this.selectedColors,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<PetColorsSelector> createState() =>
      _PetColorsSelectorState();
}

class _PetColorsSelectorState extends State<PetColorsSelector> {
  static const int maxColores = 5;

  static const List<String> coloresDisponibles = [
    'Negro',
    'Blanco',
    'Gris',
    'Café',
    'Marrón',
    'Beige',
    'Crema',
    'Dorado',
    'Amarillo',
    'Naranja',
    'Canela',
    'Chocolate',
    'Rojizo',
    'Atigrado',
    'Azul grisáceo',
  ];

  TextEditingController? _buscadorController;

  String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  void _agregarColor(String color) {
    if (!widget.enabled ||
        widget.selectedColors.length >= maxColores ||
        widget.selectedColors.contains(color)) {
      return;
    }

    widget.onChanged([
      ...widget.selectedColors,
      color,
    ]);

    _buscadorController?.clear();
  }

  void _eliminarColor(String color) {
    if (!widget.enabled) return;

    widget.onChanged(
      widget.selectedColors
          .where((item) => item != color)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final limiteAlcanzado =
        widget.selectedColors.length >= maxColores;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Colores de la mascota *',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        Autocomplete<String>(
          optionsBuilder: (textEditingValue) {
            if (!widget.enabled || limiteAlcanzado) {
              return <String>[];
            }

            final busqueda =
                _normalizar(textEditingValue.text.trim());

            return coloresDisponibles.where((color) {
              return !widget.selectedColors.contains(color) &&
                  _normalizar(color).contains(busqueda);
            });
          },

          onSelected: _agregarColor,

          fieldViewBuilder: (
            context,
            controller,
            focusNode,
            onFieldSubmitted,
          ) {
            _buscadorController = controller;

            return TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled && !limiteAlcanzado,
              decoration: InputDecoration(
                hintText: limiteAlcanzado
                    ? 'Máximo 5 colores seleccionados'
                    : 'Buscar un color...',
                prefixIcon: const Icon(
                  Icons.palette_outlined,
                  color: Color(0xFF09613D),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.selectedColors.map((color) {
            return InputChip(
              label: Text(color),
              backgroundColor: const Color(0xFFDDF3E9),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: widget.enabled
                  ? () => _eliminarColor(color)
                  : null,
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        Text(
          '${widget.selectedColors.length}/5 colores seleccionados',
          style: TextStyle(
            fontSize: 12,
            color: limiteAlcanzado
                ? const Color(0xFF09613D)
                : Colors.grey[700],
          ),
        ),
      ],
    );
  }
}
