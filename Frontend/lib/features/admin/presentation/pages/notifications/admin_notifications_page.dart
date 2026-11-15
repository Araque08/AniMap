
import 'package:flutter/material.dart';

import '../../../data/notifications/admin_notifications_service.dart';

// =====================================================
// HU-049: COMUNICADOS ADMINISTRATIVOS
// =====================================================

class AdminNotificationsPage extends StatefulWidget {
  final AdminNotificationsService? service;

  const AdminNotificationsPage({
    super.key,
    this.service,
  });

  @override
  State<AdminNotificationsPage> createState() =>
      _AdminNotificationsPageState();
}

class _AdminNotificationsPageState
    extends State<AdminNotificationsPage> {
  static const Color green = Color(0xFF3F9568);
  static const Color background = Color(0xFFF5F8F6);
  static const Color textPrimary = Color(0xFF26352E);
  static const Color textSecondary = Color(0xFF718078);

  final _formKey = GlobalKey<FormState>();

  final _tituloController = TextEditingController();
  final _mensajeController = TextEditingController();

  late final AdminNotificationsService _service =
      widget.service ?? AdminNotificationsService();

  List<Map<String, dynamic>> _audiencias = [];
  List<String> _barrios = [];

  String _audienciaSeleccionada = 'ADMINISTRADOR';
  String? _barrioSeleccionado;

  bool _cargando = true;
  bool _enviando = false;

  String? _error;

  int _consultaActual = 0;

  @override
  void initState() {
    super.initState();
    _cargarAudiencias();
  }

  @override
  void dispose() {
    _consultaActual++;
    _tituloController.dispose();
    _mensajeController.dispose();
    super.dispose();
  }

  // ===================================================
  // CONSULTAR DESTINATARIOS
  // ===================================================

  Future<void> _cargarAudiencias() async {
    final consulta = ++_consultaActual;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await _service.consultarAudiencias(
        barrio: _barrioSeleccionado,
      );

      final audienciasRespuesta = respuesta['audiencias'];
      final barriosRespuesta = respuesta['barrios'];

      if (audienciasRespuesta is! List ||
          barriosRespuesta is! List) {
        throw const AdminNotificationsException(
          'No fue posible cargar las audiencias y barrios.',
        );
      }

      final audiencias = audienciasRespuesta
          .map(
            (item) => Map<String, dynamic>.from(item as Map),
          )
          .toList();

      final barrios = barriosRespuesta
          .map((item) => item.toString())
          .toList();

      if (!mounted || consulta != _consultaActual) return;

      setState(() {
        _audiencias = audiencias;
        _barrios = barrios;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || consulta != _consultaActual) return;

      setState(() {
        _error = error.toString();
        _cargando = false;
      });
    }
  }

  // ===================================================
  // CAMBIAR BARRIO
  // ===================================================

  void _cambiarBarrio(String? valor) {
    if (_cargando || _enviando) return;

    setState(() {
      _barrioSeleccionado =
          valor == null || valor.isEmpty ? null : valor;
    });

    // Actualizar cantidades según el nuevo barrio.
    _cargarAudiencias();
  }

  // ===================================================
  // AUDIENCIA SELECCIONADA
  // ===================================================

  Map<String, dynamic> _obtenerAudiencia() {
    for (final audiencia in _audiencias) {
      if (audiencia['codigo'] == _audienciaSeleccionada) {
        return audiencia;
      }
    }

    return {};
  }

  int get _totalDestinatarios {
    final total = _obtenerAudiencia()['total'];
    return total is num ? total.toInt() : 0;
  }

  // ===================================================
  // CONFIRMAR Y REGISTRAR COMUNICADO
  // ===================================================

  Future<void> _enviarComunicado() async {
    if (_enviando || _cargando || _error != null) return;

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final titulo = _tituloController.text.trim();
    final mensaje = _mensajeController.text.trim();

    final audiencia = _audienciaSeleccionada;
    final barrio = _barrioSeleccionado;

    setState(() {
      _enviando = true;
    });

    try {
      // Refrescar el número de destinatarios
      // antes de mostrar la confirmación.
      final respuesta = await _service.consultarAudiencias(
        barrio: barrio,
      );

      final datos = respuesta['audiencias'];

      if (datos is! List) {
        throw const AdminNotificationsException(
          'No se pudo confirmar la audiencia.',
        );
      }

      final audienciasActualizadas = datos
          .map(
            (item) => Map<String, dynamic>.from(item as Map),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _audiencias = audienciasActualizadas;
      });

      final seleccionada = audienciasActualizadas
          .where((item) => item['codigo'] == audiencia)
          .toList();

      if (seleccionada.isEmpty) {
        throw const AdminNotificationsException(
          'La audiencia seleccionada no está disponible.',
        );
      }

      final nombreAudiencia =
          seleccionada.first['nombre']?.toString() ?? audiencia;

      final total =
          (seleccionada.first['total'] as num?)?.toInt() ?? 0;

      if (total <= 0) {
        throw const AdminNotificationsException(
          'No hay destinatarios habilitados para esta selección.',
        );
      }

      final barrioTexto = barrio ?? 'Todos los barrios';

      // Confirmación obligatoria.
      final confirmar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Confirmar comunicado'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Revisa la información antes de registrar el comunicado.',
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Título: $titulo',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Mensaje: $mensaje'),
                  const SizedBox(height: 12),
                  Text('Audiencia: $nombreAudiencia'),
                  const SizedBox(height: 12),
                  Text('Barrio: $barrioTexto'),
                  const SizedBox(height: 12),
                  Text(
                    'Destinatarios habilitados: $total',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: green,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'El comunicado se guardará en el historial '
                    'de los destinatarios. No se enviarán '
                    'notificaciones push todavía.',
                    style: TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                ),
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Confirmar envío'),
              ),
            ],
          );
        },
      );

      if (!mounted || confirmar != true) return;

      // El backend vuelve a filtrar los destinatarios.
      final resultado = await _service.enviarComunicado(
        titulo: titulo,
        mensaje: mensaje,
        audiencia: audiencia,
        barrio: barrio,
      );

      if (!mounted) return;

      final guardadas = resultado['guardadasEnHistorial'] ?? 0;

      _tituloController.clear();
      _mensajeController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Comunicado registrado correctamente. '
            'Notificaciones creadas: $guardadas.',
          ),
          backgroundColor: green,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$error\nVerifica el historial antes de '
            'intentar enviarlo nuevamente.',
          ),
          backgroundColor: const Color(0xFFB95050),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
        });
      }
    }
  }

  // ===================================================
  // DISEÑO
  // ===================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text(
          'Notificaciones',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: background,
      ),
      body: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 20),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
          children: [
            // ENCABEZADO
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: green,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.campaign_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Enviar comunicado',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Informa a la comunidad sobre novedades '
                    'y actualizaciones importantes de AniMap.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // FORMULARIO
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFE4EBE7),
                ),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nuevo comunicado',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // TÍTULO
                    TextFormField(
                      controller: _tituloController,
                      enabled: !_enviando,
                      maxLength: 140,
                      decoration: const InputDecoration(
                        labelText: 'Título',
                        prefixIcon: Icon(Icons.title_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().length < 3) {
                          return 'Ingresa al menos 3 caracteres.';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    // MENSAJE
                    TextFormField(
                      controller: _mensajeController,
                      enabled: !_enviando,
                      maxLength: 1000,
                      minLines: 4,
                      maxLines: 7,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().length < 5) {
                          return 'Ingresa al menos 5 caracteres.';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    // AUDIENCIA
                    const Text(
                      'Audiencia',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (_cargando && _audiencias.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_audiencias.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'admin-audience-$_audienciaSeleccionada',
                        ),
                        initialValue: _audienciaSeleccionada,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.groups_rounded),
                          border: OutlineInputBorder(),
                        ),
                        items: _audiencias.map((item) {
                          final codigo = item['codigo'].toString();
                          final nombre = item['nombre'].toString();

                          return DropdownMenuItem<String>(
                            value: codigo,
                            child: Text(
                              nombre,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: _cargando || _enviando
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _audienciaSeleccionada = value;
                                });
                              },
                      ),

                    const SizedBox(height: 18),

                    // BARRIO
                    const Text(
                      'Barrio',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (_cargando && _barrios.isEmpty)
                      const Center(
                        child: CircularProgressIndicator(),
                      )
                    else if (_barrios.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'admin-barrio-${_barrioSeleccionado ?? 'todos'}',
                        ),
                        initialValue: _barrioSeleccionado ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(
                            Icons.location_on_outlined,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text('Todos los barrios'),
                          ),
                          ..._barrios.map(
                            (barrio) => DropdownMenuItem<String>(
                              value: barrio,
                              child: Text(
                                barrio,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: _cargando || _enviando
                            ? null
                            : _cambiarBarrio,
                      ),

                    const SizedBox(height: 16),

                    // CANTIDAD DE DESTINATARIOS
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF5EF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people_outline_rounded,
                            color: green,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _cargando
                                  ? 'Actualizando destinatarios...'
                                  : 'Destinatarios habilitados: '
                                      '$_totalDestinatarios',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.red,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _enviando
                            ? null
                            : _cargarAudiencias,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Los comunicados se guardarán en el historial '
              'de AniMap. El envío push se habilitará posteriormente.',
              style: TextStyle(
                fontSize: 13,
                color: textSecondary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 22),

            // BOTÓN DE ENVÍO
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _cargando ||
                        _enviando ||
                        _error != null ||
                        _totalDestinatarios <= 0
                    ? null
                    : _enviarComunicado,
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _enviando
                      ? 'Registrando...'
                      : 'Enviar comunicado',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
