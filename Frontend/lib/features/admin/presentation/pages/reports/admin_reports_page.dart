
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


  // ========================================================
  // SECCIÓN DE POSIBLES REPORTES DUPLICADOS
  // ========================================================

  Widget _duplicatesSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _service.getPossibleDuplicates(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: CircularProgressIndicator(color: green),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No se pudieron consultar los duplicados: '
                    '${snapshot.error}',
              ),
            ),
          );
        }

        final data = snapshot.data;

        if (data == null) {
          return const SizedBox.shrink();
        }

        final duplicates =
            (data['duplicados'] as List?) ?? [];

        final total =
            (data['total'] as num?)?.toInt() ?? 0;

        final high =
            (data['prioridadAlta'] as num?)?.toInt() ?? 0;

        final medium =
            (data['prioridadMedia'] as num?)?.toInt() ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 22),
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
                    Icons.warning_amber_rounded,
                    color: Color(0xFFD68738),
                    size: 27,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Posibles reportes duplicados',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 17,
                    backgroundColor:
                    const Color(0xFFFFF2E4),
                    child: Text(
                      '$total',
                      style: const TextStyle(
                        color: Color(0xFFB66A23),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 9),

              const Text(
                'El sistema identifica reportes con '
                    'características similares para su revisión.',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 14),

              Wrap(
                spacing: 9,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(
                      Icons.priority_high,
                      size: 17,
                      color: Colors.redAccent,
                    ),
                    label: Text('Prioridad alta: $high'),
                  ),
                  Chip(
                    avatar: const Icon(
                      Icons.info_outline,
                      size: 17,
                      color: Colors.orange,
                    ),
                    label: Text('Prioridad media: $medium'),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (duplicates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text(
                      'No se encontraron posibles duplicados.',
                      style: TextStyle(
                        color: textSecondary,
                      ),
                    ),
                  ),
                )
              else
                ...duplicates.map((item) {
                  final duplicate =
                  Map<String, dynamic>.from(item as Map);

                  final report1 =
                  (duplicate['report1Id'] as num).toInt();

                  final report2 =
                  (duplicate['report2Id'] as num).toInt();

                  final score =
                      duplicate['coincidencia'] ?? 0;

                  final priority =
                      duplicate['prioridad']?.toString() ?? 'MEDIA';

                  final highPriority = priority == 'ALTA';

                  return Container(
                    margin: const EdgeInsets.only(top: 11),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: const Color(0xFFE4EBE7),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _value(
                                  duplicate['mascotaNombre'],
                                ),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              '$score%',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: highPriority
                                    ? Colors.redAccent
                                    : const Color(0xFFD68738),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 7),

                        Text(
                          'Reportes #$report1 y #$report2',
                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Tiempo: ${duplicate['diferenciaMinutos']} min',
                        ),

                        Text(
                          'Distancia: ${duplicate['distanciaMetros']} m',
                        ),

                        Text(
                          'Similitud de descripción: '
                              '${duplicate['similitudDescripcion']}%',
                        ),

                        const SizedBox(height: 10),


                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: green,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: () => _compareDuplicates(duplicate),
                            icon: const Icon(Icons.compare_arrows_rounded),
                            label: const Text('Comparar registros'),
                          ),
                        ),

                        const SizedBox(height: 10),


                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (duplicate['tipo'] == 'REPORTE') ...[
                              OutlinedButton.icon(
                                onPressed: () => _openReport(report1),
                                icon: const Icon(Icons.visibility_outlined),
                                label: Text('Ver reporte #$report1'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openReport(report2),
                                icon: const Icon(Icons.visibility_outlined),
                                label: Text('Ver reporte #$report2'),
                              ),
                            ] else if (duplicate['tipo'] == 'AVISTAMIENTO') ...[
                              OutlinedButton.icon(
                                onPressed: () => _showSightingDetails(
                                  duplicate,
                                  first: true,
                                ),
                                icon: const Icon(Icons.remove_red_eye_outlined),
                                label: Text('Ver avistamiento #$report1'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _showSightingDetails(
                                  duplicate,
                                  first: false,
                                ),
                                icon: const Icon(Icons.remove_red_eye_outlined),
                                label: Text('Ver avistamiento #$report2'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSightingDetails(
      Map<String, dynamic> duplicate, {
        required bool first,
      }) async {
    final suffix = first ? '1' : '2';

    final id = duplicate[
    first ? 'report1Id' : 'report2Id'
    ];

    final description = duplicate['descripcion$suffix'];
    final created = duplicate['creadoEn$suffix'];

    final location = duplicate['ubicacion$suffix'];

    final coordinates = location is Map
        ? Map<String, dynamic>.from(location)
        : <String, dynamic>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            'Avistamiento #$id',
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
                  _detail(
                    'Descripción',
                    description,
                  ),
                  _detail(
                    'Fecha de registro',
                    _date(created),
                  ),
                  _detail(
                    'Latitud',
                    coordinates['lat'],
                  ),
                  _detail(
                    'Longitud',
                    coordinates['lng'],
                  ),
                  _detail(
                    'Usuario creador',
                    duplicate[
                    first ? 'usuario1Id' : 'usuario2Id'
                    ],
                  ),
                  _detail(
                    'Reporte de pérdida vinculado',
                    duplicate[
                    first
                        ? 'reporteVinculado1'
                        : 'reporteVinculado2'
                    ],
                  ),
                  const Divider(height: 25),
                  _detail(
                    'Diferencia de tiempo',
                    '${duplicate['diferenciaMinutos']} minutos',
                  ),
                  _detail(
                    'Distancia entre avistamientos',
                    '${duplicate['distanciaMetros']} metros',
                  ),
                  _detail(
                    'Similitud de descripción',
                    '${duplicate['similitudDescripcion']}%',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }


  // =========================================================
  // COMPARAR POSIBLES REPORTES DUPLICADOS
  // =========================================================

  Future<void> _compareDuplicates(
      Map<String, dynamic> duplicate,
      ) async {
    final tipo = duplicate['tipo']?.toString() ?? 'REPORTE';

    final id1 = duplicate['report1Id'];
    final id2 = duplicate['report2Id'];

    final ubicacion1 = duplicate['ubicacion1'] is Map
        ? Map<String, dynamic>.from(duplicate['ubicacion1'] as Map)
        : <String, dynamic>{};

    final ubicacion2 = duplicate['ubicacion2'] is Map
        ? Map<String, dynamic>.from(duplicate['ubicacion2'] as Map)
        : <String, dynamic>{};

    Widget comparisonCard({
      required dynamic id,
      required dynamic descripcion,
      required dynamic fecha,
      required Map<String, dynamic> ubicacion,
      required dynamic usuarioId,
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE4EBE7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$tipo #$id',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _detail('Descripción', descripcion),
            _detail('Fecha', _date(fecha)),
            _detail('Usuario ID', usuarioId),
            _detail('Latitud', ubicacion['lat']),
            _detail('Longitud', ubicacion['lng']),
          ],
        ),
      );
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: const Text(
            'Comparar posibles duplicados',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 450;

                      final firstCard = comparisonCard(
                        id: id1,
                        descripcion: duplicate['descripcion1'],
                        fecha: duplicate['creadoEn1'],
                        ubicacion: ubicacion1,
                        usuarioId: duplicate['usuario1Id'],
                      );

                      final secondCard = comparisonCard(
                        id: id2,
                        descripcion: duplicate['descripcion2'],
                        fecha: duplicate['creadoEn2'],
                        ubicacion: ubicacion2,
                        usuarioId: duplicate['usuario2Id'],
                      );

                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: firstCard),
                            const SizedBox(width: 12),
                            Expanded(child: secondCard),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          firstCard,
                          const SizedBox(height: 12),
                          secondCard,
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Resultado del análisis',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _detail(
                    'Coincidencia estimada',
                    '${duplicate['coincidencia']}%',
                  ),

                  _detail(
                    'Diferencia de tiempo',
                    '${duplicate['diferenciaMinutos']} minutos',
                  ),

                  _detail(
                    'Distancia entre ubicaciones',
                    '${duplicate['distanciaMetros']} metros',
                  ),

                  _detail(
                    'Similitud de descripción',
                    '${duplicate['similitudDescripcion']}%',
                  ),

                  const Divider(height: 24),

                  const Text(
                    'Motivos de coincidencia',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  ...(duplicate['motivos'] as List? ?? [])
                      .map(
                        (motivo) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: green,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              motivo.toString(),
                              style: const TextStyle(
                                fontSize: 13,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cerrar'),
            ),

            if (duplicate['tipo'] == 'AVISTAMIENTO')
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD65A5A),
                ),
                onPressed: () {
                  // Cerrar la comparación antes de abrir
                  // el formulario de confirmación.
                  Navigator.pop(dialogContext);

                  _confirmDuplicate(duplicate);
                },
                icon: const Icon(Icons.rule_rounded),
                label: const Text('Resolver duplicado'),
              ),
          ],

        );
      },
    );
  }


  // =========================================================
  // HU-047: CONFIRMAR DUPLICADO DE AVISTAMIENTOS
  // =========================================================

  Future<void> _confirmDuplicate(
      Map<String, dynamic> duplicate,
      ) async {
    if (duplicate['tipo'] != 'AVISTAMIENTO') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta operación solo está disponible para avistamientos.',
          ),
        ),
      );
      return;
    }

    final firstId = (duplicate['report1Id'] as num).toInt();
    final secondId = (duplicate['report2Id'] as num).toInt();

    int keepId = firstId;
    bool saving = false;

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                if (saving ||
                    formKey.currentState?.validate() != true) {
                  return;
                }

                final deleteId =
                keepId == firstId ? secondId : firstId;

                final confirmed = await showDialog<bool>(
                  context: dialogContext,
                  builder: (confirmContext) => AlertDialog(
                    title: const Text('Confirmar eliminación'),
                    content: Text(
                      'Se conservará el avistamiento #$keepId '
                          'y se retirará el avistamiento #$deleteId.\n\n'
                          'También se notificará al usuario creador '
                          'del registro retirado.\n\n'
                          '¿Deseas continuar?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(confirmContext, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
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

                setDialogState(() => saving = true);

                try {
                  await _service.confirmSightingDuplicate(
                    registro1Id: firstId,
                    registro2Id: secondId,
                    conservarId: keepId,
                    motivo: reasonController.text,
                  );

                  if (!dialogContext.mounted) return;

                  Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (!dialogContext.mounted) return;

                  setDialogState(() => saving = false);

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
              }

              return PopScope(
                canPop: !saving,
                child: AlertDialog(
                  backgroundColor: Colors.white,
                  title: const Text(
                    'Resolver posible duplicado',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  content: SizedBox(
                    width: 430,
                    child: SingleChildScrollView(
                      child: Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selecciona cuál avistamiento conservar.',
                            ),
                            const SizedBox(height: 14),

                            RadioGroup<int>(
                              groupValue: keepId,
                              onChanged: (value) {
                                if (value == null || saving) return;
                                setDialogState(() => keepId = value);
                              },
                              child: Column(
                                children: [
                                  RadioListTile<int>(
                                    title: Text('Conservar #$firstId'),
                                    subtitle: Text(
                                      _value(duplicate['descripcion1']),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    value: firstId,
                                  ),
                                  RadioListTile<int>(
                                    title: Text('Conservar #$secondId'),
                                    subtitle: Text(
                                      _value(duplicate['descripcion2']),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    value: secondId,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            Text(
                              'Se eliminará el avistamiento '
                                  '#${keepId == firstId ? secondId : firstId}.',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 15),

                            TextFormField(
                              controller: reasonController,
                              enabled: !saving,
                              maxLines: 3,
                              maxLength: 500,
                              decoration: const InputDecoration(
                                labelText: 'Motivo de eliminación',
                                hintText:
                                'Explica por qué consideras que es duplicado',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final length = value?.trim().length ?? 0;
                                if (length < 10) {
                                  return 'Escribe mínimo 10 caracteres';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
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
                      onPressed: saving ? null : submit,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        saving ? 'Procesando...' : 'Eliminar duplicado',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
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
            content: Text(
              'Duplicado retirado y notificación registrada.',
            ),
            backgroundColor: green,
          ),
        );

        await _loadReports();
      }
    } finally {
      reasonController.dispose();
    }
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
            _duplicatesSection(),
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
