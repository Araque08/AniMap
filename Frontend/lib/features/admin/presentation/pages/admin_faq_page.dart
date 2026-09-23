import 'package:flutter/material.dart';

import '../../data/faq_service.dart';

class AdminFaqPage extends StatefulWidget {
  final FaqService? service;
  const AdminFaqPage({super.key, this.service});
  @override
  State<AdminFaqPage> createState() => _AdminFaqPageState();
}

class _AdminFaqPageState extends State<AdminFaqPage> {
  late final FaqService _service = widget.service ?? FaqService();
  List<Map<String, dynamic>> _faqs = [];
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
      final results = await Future.wait([
        _service.getAdminFaqs(),
        _service.getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _faqs = results[0];
        _categories = results[1];
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
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crea una categoría antes de agregar FAQ'),
        ),
      );
      return;
    }
    var question = current?['pregunta']?.toString() ?? '';
    var answer = current?['respuesta']?.toString() ?? '';
    var categoryId =
        (current?['fk_categoria'] as num?)?.toInt() ??
        (_categories.first['id'] as num).toInt();
    var active = current?['activa'] == true || current == null;
    final formKey = GlobalKey<FormState>();
    var isSubmitting = false;
    var hasCompletedSuccessfully = false;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !isSubmitting,
          child: AlertDialog(
            title: Text(current == null ? 'Crear FAQ' : 'Editar FAQ'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                        ),
                        items: _categories
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: (item['id'] as num).toInt(),
                                child: Text(
                                  item['nombre'].toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                if (value != null) {
                                  update(() => categoryId = value);
                                }
                              },
                      ),
                      TextFormField(
                        initialValue: question,
                        enabled: !isSubmitting,
                        onChanged: (value) => question = value,
                        decoration: const InputDecoration(
                          labelText: 'Pregunta',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Ingresa la pregunta'
                            : null,
                      ),
                      TextFormField(
                        initialValue: answer,
                        enabled: !isSubmitting,
                        onChanged: (value) => answer = value,
                        decoration: const InputDecoration(
                          labelText: 'Respuesta',
                        ),
                        maxLines: 4,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Ingresa la respuesta'
                            : null,
                      ),
                      SwitchListTile(
                        title: const Text('Activa'),
                        value: active,
                        onChanged: isSubmitting
                            ? null
                            : (value) => update(() => active = value),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (isSubmitting || hasCompletedSuccessfully) return;
                        if (!formKey.currentState!.validate()) return;
                        update(() => isSubmitting = true);
                        final input = {
                          'categoriaId': categoryId,
                          'pregunta': question.trim(),
                          'respuesta': answer.trim(),
                          'activa': active,
                        };
                        try {
                          if (current == null) {
                            await _service.createFaq(input);
                          } else {
                            await _service.updateFaq(
                              (current['id'] as num).toInt(),
                              input,
                            );
                          }
                          if (!mounted || !dialogContext.mounted) return;
                          hasCompletedSuccessfully = true;
                          final navigator = Navigator.of(dialogContext);
                          if (navigator.canPop()) navigator.pop(true);
                        } catch (error) {
                          if (dialogContext.mounted &&
                              !hasCompletedSuccessfully) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error is FaqException
                                      ? error.message
                                      : 'No pudimos guardar la pregunta frecuente. Intenta nuevamente.',
                                ),
                              ),
                            );
                          }
                        } finally {
                          if (dialogContext.mounted &&
                              !hasCompletedSuccessfully) {
                            update(() => isSubmitting = false);
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) await _load();
  }

  Future<void> _toggle(Map<String, dynamic> faq) async {
    try {
      await _service.setFaqStatus(
        (faq['id'] as num).toInt(),
        faq['activa'] != true,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> faq) async {
    final id = (faq['id'] as num).toInt();
    var deleting = false;
    String? dialogError;
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Eliminar pregunta frecuente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿Seguro que deseas eliminar esta pregunta frecuente? Esta acción no se puede deshacer.',
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 12),
                Text(
                  dialogError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: deleting
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: deleting
                  ? null
                  : () async {
                      if (deleting) return;
                      update(() {
                        deleting = true;
                        dialogError = null;
                      });
                      try {
                        await _service.deleteFaq(id);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        update(() {
                          deleting = false;
                          dialogError = error is FaqException
                              ? error.message
                              : 'No pudimos eliminar la pregunta frecuente. Intenta nuevamente.';
                        });
                      }
                    },
              child: deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );
    if (deleted != true || !mounted) return;
    setState(() => _faqs.removeWhere((item) => item['id'] == id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pregunta frecuente eliminada correctamente'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7FAF8),
    appBar: AppBar(title: const Text('Preguntas frecuentes')),
    floatingActionButton: FloatingActionButton.extended(
      backgroundColor: const Color(0xFF3F9568),
      foregroundColor: Colors.white,
      onPressed: () => _edit(null),
      icon: const Icon(Icons.add),
      label: const Text('Agregar FAQ'),
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
              itemCount: _faqs.length,
              itemBuilder: (context, index) => LayoutBuilder(
                builder: (context, constraints) {
                  final faq = _faqs[index];
                  final archived = faq['activa'] != true;
                  final compact = constraints.maxWidth <= 360;
                  final status = archived
                      ? Row(
                          children: [
                            Flexible(
                              child: Text(
                                faq['categoria']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6C7478),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              key: const ValueKey('archived-faq-badge'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFCFD8DC),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'ARCHIVADA',
                                style: TextStyle(
                                  color: Color(0xFF455A64),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text('${faq['categoria'] ?? ''} · Activa');
                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Editar FAQ',
                        onPressed: () => _edit(faq),
                        icon: Icon(
                          Icons.edit_outlined,
                          color: archived ? const Color(0xFF7B8387) : null,
                        ),
                      ),
                      IconButton(
                        tooltip: faq['activa'] == true
                            ? 'Archivar FAQ'
                            : 'Activar FAQ',
                        onPressed: () => _toggle(faq),
                        icon: Icon(
                          !archived
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: archived ? const Color(0xFF2E7D5B) : null,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Eliminar FAQ',
                        onPressed: () => _delete(faq),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFB04A48),
                        ),
                      ),
                    ],
                  );
                  final tile = ListTile(
                    title: Text(
                      faq['pregunta']?.toString() ?? '',
                      style: archived
                          ? const TextStyle(color: Color(0xFF596168))
                          : null,
                    ),
                    subtitle: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              status,
                              Align(
                                alignment: Alignment.centerRight,
                                child: actions,
                              ),
                            ],
                          )
                        : status,
                    isThreeLine: compact,
                    trailing: compact ? null : actions,
                  );
                  return Card(
                    color: archived ? const Color(0xFFECEFF1) : Colors.white,
                    child: archived
                        ? DecoratedBox(
                            key: const ValueKey('archived-faq-indicator'),
                            decoration: const BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: Color(0xFF90A4AE),
                                  width: 4,
                                ),
                              ),
                            ),
                            child: tile,
                          )
                        : tile,
                  );
                },
              ),
            ),
          ),
  );
}
