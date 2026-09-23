import 'package:flutter/material.dart';

import '../../data/faq_service.dart';

class AdminFaqCategoriesPage extends StatefulWidget {
  final FaqService? service;
  const AdminFaqCategoriesPage({super.key, this.service});
  @override
  State<AdminFaqCategoriesPage> createState() => _AdminFaqCategoriesPageState();
}

class _AdminFaqCategoriesPageState extends State<AdminFaqCategoriesPage> {
  late final FaqService _service = widget.service ?? FaqService();
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = await _service.getCategories();
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

  Future<void> _edit(Map<String, dynamic>? current) async {
    var name = current?['nombre']?.toString() ?? '';
    var description = current?['descripcion']?.toString() ?? '';
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(current == null ? 'Crear categoría' : 'Editar categoría'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: name,
                  onChanged: (value) => name = value,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Ingresa el nombre'
                      : null,
                ),
                TextFormField(
                  initialValue: description,
                  onChanged: (value) => description = value,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Descripción opcional',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!key.currentState!.validate()) return;
              try {
                if (current == null) {
                  await _service.createCategory(
                    name.trim(),
                    description.trim().isEmpty ? null : description.trim(),
                  );
                } else {
                  await _service.updateCategory(
                    (current['id'] as num).toInt(),
                    name.trim(),
                    description.trim().isEmpty ? null : description.trim(),
                  );
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> category) async {
    if ((category['total_faq'] as num?) != null &&
        (category['total_faq'] as num) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La categoría tiene FAQ asociadas')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar ${category['nombre']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteCategory((category['id'] as num).toInt());
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7FAF8),
    appBar: AppBar(title: const Text('Categorías FAQ')),
    floatingActionButton: FloatingActionButton.extended(
      backgroundColor: const Color(0xFF3F9568),
      foregroundColor: Colors.white,
      onPressed: () => _edit(null),
      icon: const Icon(Icons.add),
      label: const Text('Agregar categoría'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Reintentar')),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                return Card(
                  color: Colors.white,
                  child: ListTile(
                    title: Text(category['nombre']?.toString() ?? ''),
                    subtitle: Text('${category['total_faq'] ?? 0} preguntas'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Editar categoría',
                          onPressed: () => _edit(category),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Eliminar categoría',
                          onPressed: () => _delete(category),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
  );
}
