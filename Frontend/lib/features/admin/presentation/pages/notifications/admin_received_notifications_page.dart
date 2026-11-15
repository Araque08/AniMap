
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../auth/data/auth_service.dart';
import '../../../../auth/data/authenticated_http_client.dart';

// =====================================================
// HU-049: NOTIFICACIONES RECIBIDAS POR ADMINISTRADORES
// =====================================================

class AdminReceivedNotificationsPage extends StatefulWidget {
  const AdminReceivedNotificationsPage({super.key});

  @override
  State<AdminReceivedNotificationsPage> createState() =>
      _AdminReceivedNotificationsPageState();
}

class _AdminReceivedNotificationsPageState
    extends State<AdminReceivedNotificationsPage> {

  static const Color green = Color(0xFF3F9568);
  static const Color background = Color(0xFFF5F8F6);

  final _client = AuthenticatedHttpClient.instance;

  List<Map<String, dynamic>> _notificaciones = [];

  bool _cargando = false;
  bool _cargandoMas = false;
  bool _hayMas = false;

  int _pagina = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarNotificaciones();
  }

  // ===================================================
  // CONSULTAR HISTORIAL
  // ===================================================

  Future<void> _cargarNotificaciones({
    bool cargarMas = false,
  }) async {

    if (_cargando || _cargandoMas) return;

    final paginaSolicitada =
        cargarMas ? _pagina + 1 : 1;

    setState(() {
      if (cargarMas) {
        _cargandoMas = true;
      } else {
        _cargando = true;
      }

      _error = null;
    });

    try {
      final url = Uri.parse(
        '${AuthService.baseUrl}/notifications'
        '?pagina=$paginaSolicitada',
      );

      final response = await _client.get(url);

      final decoded = jsonDecode(response.body);

      if (response.statusCode != 200 ||
          decoded is! Map ||
          decoded['ok'] != true) {
        throw Exception(
          decoded is Map
              ? decoded['message']?.toString() ??
                  'No se pudo consultar el historial.'
              : 'Respuesta inválida del servidor.',
        );
      }

      final data = decoded['data'];

      if (data is! Map ||
          data['notificaciones'] is! List) {
        throw Exception(
          'El historial recibido no es válido.',
        );
      }

      final registros = (data['notificaciones'] as List)
          .map(
            (item) =>
                Map<String, dynamic>.from(item as Map),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        if (cargarMas) {
          final idsExistentes = _notificaciones
              .map((item) => item['id'])
              .toSet();

          _notificaciones.addAll(
            registros.where(
              (item) => !idsExistentes.contains(item['id']),
            ),
          );
        } else {
          _notificaciones = registros;
        }

        _pagina = paginaSolicitada;
        _hayMas = data['hayMas'] == true;
      });

    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });

    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
          _cargandoMas = false;
        });
      }
    }
  }

  // ===================================================
  // MARCAR COMO LEÍDA
  // ===================================================

  Future<void> _abrirNotificacion(
    Map<String, dynamic> notificacion,
  ) async {

    final id = (notificacion['id'] as num?)?.toInt();

    if (id == null) return;

    // Marcar como leída únicamente si está pendiente.
    if (notificacion['leida'] != true) {
      try {
        final response = await _client.patch(
          Uri.parse(
            '${AuthService.baseUrl}/notifications/$id/read',
          ),
        );

        final decoded = jsonDecode(response.body);

        if (response.statusCode != 200 ||
            decoded is! Map ||
            decoded['ok'] != true) {
          throw Exception(
            'No fue posible marcar la notificación como leída.',
          );
        }

        if (!mounted) return;

        setState(() {
          for (final item in _notificaciones) {
            if (item['id'] == id) {
              item['leida'] = true;
            }
          }
        });

      } catch (error) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
          ),
        );
      }
    }

    if (!mounted) return;

    // Mostrar mensaje completo.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            notificacion['titulo']?.toString() ??
                'Notificación',
          ),
          content: SingleChildScrollView(
            child: Text(
              notificacion['mensaje']?.toString() ?? '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  // ===================================================
  // FECHA
  // ===================================================

  String _formatearFecha(dynamic valor) {
    final fecha = DateTime.tryParse(
      valor?.toString() ?? '',
    )?.toLocal();

    if (fecha == null) return '';

    String dos(int numero) =>
        numero.toString().padLeft(2, '0');

    return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} '
        '${dos(fecha.hour)}:${dos(fecha.minute)}';
  }

  // ===================================================
  // INTERFAZ
  // ===================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        title: const Text('Mis notificaciones'),
        backgroundColor: background,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando || _cargandoMas
                ? null
                : () => _cargarNotificaciones(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),

      body: SafeArea(
        child: Column(
          children: [

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),

            Expanded(
              child: _cargando && _notificaciones.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargarNotificaciones,
                      child: _notificaciones.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 130),
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: 65,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Center(
                                  child: Text(
                                    'No tienes notificaciones.',
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),

                              itemCount: _notificaciones.length,

                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),

                              itemBuilder: (context, index) {
                                final item = _notificaciones[index];

                                final leida =
                                    item['leida'] == true;

                                return Material(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(16),

                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.all(14),

                                    leading: Icon(
                                      leida
                                          ? Icons.notifications_none
                                          : Icons.notifications_active,
                                      color: green,
                                    ),

                                    title: Text(
                                      item['titulo']?.toString() ??
                                          'Notificación',
                                      style: TextStyle(
                                        fontWeight: leida
                                            ? FontWeight.normal
                                            : FontWeight.bold,
                                      ),
                                    ),

                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(
                                        top: 8,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['mensaje']?.toString() ??
                                                '',
                                            maxLines: 2,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _formatearFecha(
                                              item['fecha'],
                                            ),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    onTap: () =>
                                        _abrirNotificacion(item),
                                  ),
                                );
                              },
                            ),
                    ),
            ),

            if (_hayMas)
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: _cargandoMas
                      ? null
                      : () => _cargarNotificaciones(
                            cargarMas: true,
                          ),
                  child: Text(
                    _cargandoMas
                        ? 'Cargando...'
                        : 'Cargar más notificaciones',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
