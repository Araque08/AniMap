
import 'package:flutter/material.dart';

import '../../../data/reports/admin_reports_service.dart';

class AdminReportsPage extends StatefulWidget {
  final AdminReportsService? service;

  const AdminReportsPage({
    super.key,
    this.service,
  });

  @override
  State<AdminReportsPage> createState() =>
      _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  static const Color green = Color(0xFF3F9568);
  static const Color background = Color(0xFFF5F8F6);
  static const Color textPrimary = Color(0xFF26352E);
  static const Color textSecondary = Color(0xFF718078);

  late final AdminReportsService _service =
      widget.service ?? AdminReportsService();

  final TextEditingController _searchController =
  TextEditingController();

  List<Map<String, dynamic>> _reports = [];

  bool _loading = true;
  String? _error;
  String? _estado;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _generation++;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    final generation = ++_generation;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final reports = await _service.getReports(
        search: _searchController.text,
        estado: _estado,
      );

      if (!mounted || generation != _generation) return;

      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _value(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return 'No registrado';
    }
    return value.toString();
  }

  String _date(dynamic value) {
    if (value == null) return 'No registrada';

    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();

    final local = date.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVO':
        return green;
      case 'FINALIZADO':
        return const Color(0xFF5279A5);
      default:
        return const Color(0xFF8A7780);
    }
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
      String hint,
      IconData icon,
      ) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: textSecondary),
      prefixIcon: Icon(icon, color: textSecondary),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFE3EAE6),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFE3EAE6),
        ),
      ),
    );
  }


  // ========================================================
  // HU-076: VER DETALLE Y MODIFICAR ESTADOS
  // ========================================================

  Future<void> _openReport(int id) async {
    try {
      final report = await _service.getReport(id);

      if (!mounted) return;

      String estadoReporte =
          report['estado']?.toString().toUpperCase() ?? 'ACTIVO';

      String estadoMascota =
          report['mascotaEstado']?.toString().toUpperCase() ??
              'PERDIDA';

      bool saving = false;

      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              const combinations = <String, List<String>>{
                'ACTIVO': ['PERDIDA'],
                'FINALIZADO': ['ACTIVA', 'ENCONTRADA'],
              };

              final validCombination =
                  combinations[estadoReporte]?.contains(estadoMascota) ??
                      false;

              final originalReport =
              report['estado']?.toString().toUpperCase();

              final originalPet =
              report['mascotaEstado']?.toString().toUpperCase();

              final hasChanges =
                  estadoReporte != originalReport ||
                      estadoMascota != originalPet;

              Future<void> saveChanges() async {
                if (saving || !validCombination || !hasChanges) {
                  return;
                }

                final confirmed = await showDialog<bool>(
                  context: dialogContext,
                  builder: (confirmContext) => AlertDialog(
                    title: const Text('Confirmar cambios'),
                    content: Text(
                      '¿Deseas actualizar el reporte a '
                          '$estadoReporte y la mascota a $estadoMascota?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(confirmContext, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(confirmContext, true),
                        child: const Text('Confirmar'),
                      ),
                    ],
                  ),
                );

                if (confirmed != true || !dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  saving = true;
                });

                try {
                  await _service.updateReportStatus(
                    reportId: id,
                    estadoReporte: estadoReporte,
                    estadoMascota: estadoMascota,
                  );

                  if (!dialogContext.mounted) return;

                  Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (!dialogContext.mounted) return;

                  setDialogState(() {
                    saving = false;
                  });

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(error.toString()),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }

              return PopScope(
                canPop: !saving,
                child: AlertDialog(
                  backgroundColor: Colors.white,
                  title: Text(
                    'Reporte #$id',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  content: SizedBox(
                    width: 430,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _detail('Mascota', report['mascotaNombre']),
                          _detail('Especie', report['especie']),
                          _detail('Raza', report['raza']),
                          _detail('Color', report['mascotaColor']),
                          const Divider(height: 25),

                          _detail('Usuario', report['usuarioNombre']),
                          _detail('Correo', report['usuarioEmail']),
                          _detail('Teléfono', report['usuarioTelefono']),
                          const Divider(height: 25),

                          _detail('Descripción', report['descripcion']),
                          _detail('Dirección', report['direccion']),
                          _detail(
                            'Fecha de creación',
                            _date(report['creadoEn']),
                          ),

                          const Divider(height: 30),

                          const Text(
                            'Administrar estados',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),

                          const SizedBox(height: 15),

                          DropdownButtonFormField<String>(
                            key: ValueKey('report-$estadoReporte'),
                            initialValue: estadoReporte,
                            decoration: _inputDecoration(
                              'Estado del reporte',
                              Icons.flag_outlined,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'ACTIVO',
                                child: Text('Activo'),
                              ),
                              DropdownMenuItem(
                                value: 'FINALIZADO',
                                child: Text('Finalizado'),
                              ),
                            ],
                            onChanged: saving
                                ? null
                                : (value) {
                              if (value == null) return;

                              setDialogState(() {
                                estadoReporte = value;

                                if (value == 'ACTIVO') {
                                  estadoMascota = 'PERDIDA';
                                } else if (estadoMascota == 'PERDIDA') {
                                  estadoMascota = 'ENCONTRADA';
                                }
                              });
                            },
                          ),

                          const SizedBox(height: 15),

                          DropdownButtonFormField<String>(
                            key: ValueKey('pet-$estadoMascota'),
                            initialValue: estadoMascota,
                            decoration: _inputDecoration(
                              'Estado de la mascota',
                              Icons.pets_outlined,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'PERDIDA',
                                child: Text('Perdida'),
                              ),
                              DropdownMenuItem(
                                value: 'ACTIVA',
                                child: Text('Activa'),
                              ),
                              DropdownMenuItem(
                                value: 'ENCONTRADA',
                                child: Text('Encontrada'),
                              ),
                            ],
                            onChanged: saving
                                ? null
                                : (value) {
                              if (value == null) return;

                              setDialogState(() {
                                estadoMascota = value;
                              });
                            },
                          ),

                          if (!validCombination) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Los estados seleccionados no son compatibles.',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                      ),
                      onPressed: saving ||
                          !validCombination ||
                          !hasChanges
                          ? null
                          : saveChanges,
                      icon: saving
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        saving ? 'Guardando...' : 'Guardar cambios',
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      if (!mounted) return;

      if (changed == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Estados actualizados correctamente'),
            backgroundColor: green,
          ),
        );

        await _loadReports();
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }


  Widget _detail(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _value(value),
            style: const TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final id = int.tryParse('${report['id']}');
    final status = _value(report['estado']);

    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: const Color(0xFFE4EBE7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pets_rounded,
                color: green,
                size: 22,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _value(report['mascotaNombre']),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
              ),
              _statusBadge(status),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'Reporte #${_value(report['id'])}',
            style: const TextStyle(
              color: textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Usuario: ${_value(report['usuarioNombre'])}',
            style: const TextStyle(color: textPrimary),
          ),
          const SizedBox(height: 5),
          Text(
            'Estado de mascota: ${_value(report['mascotaEstado'])}',
            style: const TextStyle(color: textSecondary),
          ),
          const SizedBox(height: 5),
          Text(
            'Creado: ${_date(report['creadoEn'])}',
            style: const TextStyle(
              fontSize: 12,
              color: textSecondary,
            ),
          ),
          const Divider(height: 25),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: id == null
                  ? null
                  : () => _openReport(id),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Ver detalles'),
              style: TextButton.styleFrom(
                foregroundColor: green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        foregroundColor: textPrimary,
        title: const Text(
          'Gestión de reportes',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadReports,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: green,
        onRefresh: _loadReports,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Consulta y administra los reportes registrados.',
              style: TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadReports(),
              decoration: _inputDecoration(
                'Buscar mascota, usuario o ID',
                Icons.search_rounded,
              ).copyWith(
                suffixIcon: IconButton(
                  tooltip: 'Buscar',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: _loadReports,
                ),
              ),
            ),

            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              initialValue: _estado ?? 'TODOS',
              decoration: _inputDecoration(
                'Estado del reporte',
                Icons.filter_list_rounded,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'TODOS',
                  child: Text('Todos los reportes'),
                ),
                DropdownMenuItem(
                  value: 'ACTIVO',
                  child: Text('Activos'),
                ),
                DropdownMenuItem(
                  value: 'FINALIZADO',
                  child: Text('Finalizados'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _estado = value == 'TODOS' ? null : value;
                });
                _loadReports();
              },
            ),

            const SizedBox(height: 20),

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(35),
                  child: CircularProgressIndicator(color: green),
                ),
              )
            else if (_error != null)
              Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 38,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: _loadReports,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else if (_reports.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 55,
                          color: textSecondary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No se encontraron reportes',
                          style: TextStyle(color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                  Text(
                    '${_reports.length} reportes encontrados',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._reports.map(_reportCard),
                ],
          ],
        ),
      ),
    );
  }
}
