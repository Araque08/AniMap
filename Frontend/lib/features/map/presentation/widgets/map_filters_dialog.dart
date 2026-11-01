import 'package:flutter/material.dart';
import '../../data/map_filter_selection.dart';

class MapFiltersDialog extends StatefulWidget {
  final MapFilterSelection selection;
  final List<String> species;
  final List<String> colors;
  const MapFiltersDialog({
    super.key,
    required this.selection,
    required this.species,
    required this.colors,
  });

  @override
  State<MapFiltersDialog> createState() => _MapFiltersDialogState();
}

class _MapFiltersDialogState extends State<MapFiltersDialog> {
  String? _species;
  String? _color;
  DateTimeRange? _dates;

  @override
  void initState() {
    super.initState();
    _species = widget.selection.species;
    _color = widget.selection.color;
    if (widget.selection.from != null && widget.selection.to != null) {
      _dates = DateTimeRange(
        start: widget.selection.from!,
        end: widget.selection.to!,
      );
    }
  }

  Future<void> _pickDates() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _dates,
      helpText: 'Fecha del evento',
      saveText: 'Usar fechas',
    );
    if (mounted && result != null) setState(() => _dates = result);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Filtrar reportes'),
    content: SizedBox(
      width: 320,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('map-species-filter'),
              initialValue: _species,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Especie'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Todas las especies'),
                ),
                ...widget.species.map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _species = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('map-color-filter'),
              initialValue: _color,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Color'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Todos los colores'),
                ),
                ...widget.colors.map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _color = value),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('map-date-filter'),
              onPressed: _pickDates,
              icon: const Icon(Icons.date_range),
              label: Text(
                _dates == null
                    ? 'Todas las fechas'
                    : '${_date(_dates!.start)} – ${_date(_dates!.end)}',
              ),
            ),
            if (_dates != null)
              TextButton(
                onPressed: () => setState(() => _dates = null),
                child: const Text('Quitar fechas'),
              ),
            const Text(
              'Fecha de creación, avistamiento o cierre en Encontrados. Los registros sin especie/color conocidos no coinciden con esos filtros.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          MapFilterSelection(
            species: _species,
            color: _color,
            from: _dates?.start,
            to: _dates?.end,
          ),
        ),
        child: const Text('Aplicar filtros'),
      ),
    ],
  );

  String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
}
