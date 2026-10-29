import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Pantalla de consulta de la bitácora administrativa de AniMap.
///
/// Ejemplo de uso:
/// AdminBitacoraPage(
///   baseUrl: 'http://TU_IP:3000/api',
///   token: tokenDeSesion,
/// )
///
/// El backend debe responder a GET /admin/bitacora con una lista JSON,
/// o con {"registros": [ ... ]}.
class AdminBitacoraPage extends StatefulWidget {
  const AdminBitacoraPage({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  final String baseUrl;
  final String token;

  @override
  State<AdminBitacoraPage> createState() => _AdminBitacoraPageState();
}

class _AdminBitacoraPageState extends State<AdminBitacoraPage> {
  static const Color _verde = Color(0xFF7CC484);
  final TextEditingController _busquedaController = TextEditingController();

  List<RegistroBitacora> _registros = [];
  bool _cargando = true;
  String? _error;
  String _accionSeleccionada = 'Todas';
  String _moduloSeleccionado = 'Todos';
  DateTime? _fechaSeleccionada;

  @override
  void initState() {
    super.initState();
    _cargarRegistros();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _cargarRegistros() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      if (widget.baseUrl.trim().isEmpty || widget.token.trim().isEmpty) {
        throw Exception(
            'La pantalla ya está disponible, pero falta conectar la URL de la API '
                'y el token de la sesión administrativa para consultar los registros.'
        );
      }
      final base = widget.baseUrl.replaceAll(RegExp(r'/$'), '');
      final List<dynamic> todos = [];
      int pagina = 1;
      while (true) {
        final uri = Uri.parse('$base/admin/bitacora').replace(
          queryParameters: {'pagina': '$pagina', 'limite': '100'},
        );
        final respuesta = await http.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer ${widget.token}',
          },
        ).timeout(const Duration(seconds: 15));

        if (respuesta.statusCode == 401) {
          throw Exception('Tu sesión expiró o fue revocada. Ingresa nuevamente.');
        }
        if (respuesta.statusCode == 403) {
          throw Exception('Tu cuenta no tiene permisos de administrador.');
        }
        if (respuesta.statusCode != 200) {
          throw Exception('No se pudo consultar la bitácora (HTTP ${respuesta.statusCode}).');
        }

        final dynamic datos = jsonDecode(utf8.decode(respuesta.bodyBytes));
        final dynamic lista;
        if (datos is List) {
          lista = datos;
        } else if (datos is Map<String, dynamic>) {
          lista = datos['registros'] ?? datos['data'];
        } else {
          throw const FormatException('Respuesta inesperada del servidor.');
        }
        if (lista is! List) {
          throw const FormatException('La respuesta no contiene una lista de registros.');
        }
        todos.addAll(lista);
        if (lista.isEmpty) break;
        if (datos is! Map<String, dynamic> || datos['paginacion'] is! Map) break;
        final paginacion = datos['paginacion'] as Map;
        final totalPaginas = int.tryParse('${paginacion['totalPaginas']}') ?? 1;
        if (pagina >= totalPaginas) break;
        pagina++;
      }

      final lista = todos;
      final registros = lista
          .map((item) => RegistroBitacora.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) => b.fechaHora.compareTo(a.fechaHora));

      if (!mounted) return;
      setState(() => _registros = registros);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<String> _opciones(String Function(RegistroBitacora) obtener, String todas) {
    final valores = _registros.map(obtener).where((s) => s.trim().isNotEmpty).toSet().toList()..sort();
    return [todas, ...valores];
  }

  List<RegistroBitacora> get _filtrados {
    final texto = _busquedaController.text.toLowerCase().trim();
    return _registros.where((r) {
      final coincideAccion = _accionSeleccionada == 'Todas' || r.accion == _accionSeleccionada;
      final coincideModulo = _moduloSeleccionado == 'Todos' || r.modulo == _moduloSeleccionado;
      final coincideFecha = _fechaSeleccionada == null ||
          (r.fechaHora.year == _fechaSeleccionada!.year &&
              r.fechaHora.month == _fechaSeleccionada!.month &&
              r.fechaHora.day == _fechaSeleccionada!.day);
      final contenido = '${r.administrador} ${r.fkAdmin} ${r.accion} ${r.modulo} '
          '${r.entidadAfectada} ${r.idEntidadAfectada ?? ''} ${r.motivo ?? ''} ${r.detalle ?? ''}'
          .toLowerCase();
      return coincideAccion && coincideModulo && coincideFecha && contenido.contains(texto);
    }).toList();
  }

  String _fecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  String _hora(DateTime fecha) =>
      '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fecha != null && mounted) setState(() => _fechaSeleccionada = fecha);
  }

  void _mostrarDetalles(RegistroBitacora r) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle de la actividad'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _dato('Registro', '#${r.id}'),
              _dato('Administrador', r.administrador),
              _dato('ID administrador', '${r.fkAdmin}'),
              _dato('Módulo', r.modulo),
              _dato('Acción', r.accion),
              _dato('Entidad afectada', r.entidadAfectada),
              _dato('ID entidad', r.idEntidadAfectada?.toString() ?? 'No aplica'),
              _dato('Motivo', r.motivo?.isNotEmpty == true ? r.motivo! : 'No registrado'),
              _dato('Detalle', r.detalle?.isNotEmpty == true ? r.detalle! : 'No registrado'),
              _dato('Fecha', _fecha(r.fechaHora)),
              _dato('Hora', _hora(r.fechaHora)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _dato(String titulo, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
        const SizedBox(height: 2),
        SelectableText(valor),
      ],
    ),
  );

  Widget _selector({
    required String titulo,
    required String valor,
    required List<String> opciones,
    required ValueChanged<String?> cambiar,
  }) {
    return DropdownButtonFormField<String>(
      value: opciones.contains(valor) ? valor : opciones.first,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: titulo,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      ),
      items: opciones.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: cambiar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F5),
      appBar: AppBar(
        backgroundColor: _verde,
        title: const Text('Bitácora administrativa'),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargarRegistros, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarRegistros,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Historial de acciones', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Consulta los cambios realizados desde el panel de administración.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _busquedaController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Buscar administrador, acción o elemento',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _selector(
                      titulo: 'Módulo',
                      valor: _moduloSeleccionado,
                      opciones: _opciones((r) => r.modulo, 'Todos'),
                      cambiar: (v) => setState(() => _moduloSeleccionado = v ?? 'Todos'),
                    ),
                    const SizedBox(height: 12),
                    _selector(
                      titulo: 'Tipo de acción',
                      valor: _accionSeleccionada,
                      opciones: _opciones((r) => r.accion, 'Todas'),
                      cambiar: (v) => setState(() => _accionSeleccionada = v ?? 'Todas'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _elegirFecha,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_fechaSeleccionada == null ? 'Filtrar por fecha' : _fecha(_fechaSeleccionada!)),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _moduloSeleccionado = 'Todos';
                        _accionSeleccionada = 'Todas';
                        _fechaSeleccionada = null;
                        _busquedaController.clear();
                      }),
                      icon: const Icon(Icons.filter_alt_off),
                      label: const Text('Limpiar filtros'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_cargando)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(onPressed: _cargarRegistros, child: const Text('Reintentar')),
                  ]),
                ),
              )
            else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${filtrados.length} registro(s) encontrado(s)', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (filtrados.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(children: [
                        Icon(Icons.history, size: 52, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No hay registros para mostrar.', textAlign: TextAlign.center),
                      ]),
                    ),
                  )
                else
                  ...filtrados.map((r) => Card(
                    elevation: 0,
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _mostrarDetalles(r),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const CircleAvatar(backgroundColor: Color(0xFFE4F5E5), child: Icon(Icons.manage_accounts, color: Color(0xFF337E40))),
                              const SizedBox(width: 10),
                              Expanded(child: Text(r.accion, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ]),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 7, children: [
                              Chip(label: Text(r.modulo), visualDensity: VisualDensity.compact),
                              Chip(label: Text(r.entidadAfectada), visualDensity: VisualDensity.compact),
                            ]),
                            const SizedBox(height: 6),
                            Text('Administrador: ${r.administrador}'),
                            Text('Elemento afectado: ${r.entidadAfectada}${r.idEntidadAfectada != null ? ' #${r.idEntidadAfectada}' : ''}'),
                            const SizedBox(height: 8),
                            Row(children: [
                              const Icon(Icons.event, size: 16, color: Colors.black54),
                              const SizedBox(width: 4),
                              Text(_fecha(r.fechaHora)),
                              const SizedBox(width: 14),
                              const Icon(Icons.access_time, size: 16, color: Colors.black54),
                              const SizedBox(width: 4),
                              Text(_hora(r.fechaHora)),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  )),
              ],
          ],
        ),
      ),
    );
  }
}

class RegistroBitacora {
  const RegistroBitacora({
    required this.id,
    required this.fkAdmin,
    required this.administrador,
    required this.modulo,
    required this.accion,
    required this.entidadAfectada,
    required this.idEntidadAfectada,
    required this.motivo,
    required this.detalle,
    required this.fechaHora,
  });

  final int id;
  final int fkAdmin;
  final String administrador;
  final String modulo;
  final String accion;
  final String entidadAfectada;
  final int? idEntidadAfectada;
  final String? motivo;
  final String? detalle;
  final DateTime fechaHora;

  factory RegistroBitacora.fromJson(Map<String, dynamic> json) {
    int entero(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    int? enteroOpcional(dynamic v) => v == null ? null : int.tryParse('$v');
    final admin = json['administrador'] ?? json['nombre_admin'] ?? json['admin_nombre'];
    final idAdmin = entero(json['fk_admin']);
    return RegistroBitacora(
      id: entero(json['id']),
      fkAdmin: idAdmin,
      administrador: admin == null || '$admin'.trim().isEmpty ? 'Administrador #$idAdmin' : '$admin',
      modulo: '${json['modulo'] ?? 'Sin módulo'}',
      accion: '${json['accion'] ?? 'Sin acción'}',
      entidadAfectada: '${json['entidad_afectada'] ?? 'No especificada'}',
      idEntidadAfectada: enteroOpcional(json['id_entidad_afectada']),
      motivo: json['motivo']?.toString(),
      detalle: json['detalle']?.toString(),
      fechaHora: DateTime.tryParse('${json['fecha_hora'] ?? ''}') ?? DateTime(1970),
    );
  }
}