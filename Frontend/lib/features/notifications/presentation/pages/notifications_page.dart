import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/notification_history_service.dart';
import '../../../map/presentation/pages/map_page.dart';
import '../../data/notification_target_service.dart';
import '../../../auth/data/session_manager.dart';
import '../../../report/data/photo_matches_service.dart';
import '../../../report/presentation/pages/photo_matches_page.dart';


class NotificationsPage extends StatefulWidget {
  final int? initialNotificationId;

  const NotificationsPage({
    super.key,
    this.initialNotificationId,
  });


  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Timer? _autoRefreshTimer;
  bool _autoRefreshing = false;
  static const Color primaryGreen = Color(0xFF3F9568);
  static const Color backgroundColor = Color(0xFFF3F7F4);
  static const Color darkText = Color(0xFF344955);

  List<AnimapNotification> _notifications = [];

  final Set<int> _markingAsRead = {};


  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;

  bool _notificacionInicialAbierta = false;

  int _page = 0;
  String? _error;

  @override
  void initState() {
    super.initState();

    _loadNotifications();

    // Consultar nuevas notificaciones cada 20 segundos.
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted ||
          _loading ||
          _loadingMore ||
          _autoRefreshing ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      unawaited(_refreshAutomatically());
    });
  }

  @override
  void dispose() {
    // Detener las consultas cuando se cierre la pantalla.
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // =====================================================
  // HU-070: CONSULTAR HISTORIAL
  // =====================================================

  Future<void> _loadNotifications({bool loadMore = false}) async {
    if (loadMore) {
      if (_loading || _loadingMore || !_hasMore) return;

      setState(() => _loadingMore = true);
    } else {
      if (_loadingMore || _loading) {
        // Permitir la primera carga del initState.
        if (_page != 0) return;
      }

      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await NotificationHistoryService.obtenerHistorial(
        pagina: loadMore ? _page + 1 : 1,
      );

      if (!mounted) return;

      setState(() {
        if (loadMore) {
          final ids = _notifications.map((n) => n.id).toSet();

          _notifications.addAll(
            result.notificaciones.where((n) => ids.add(n.id)),
          );
        } else {
          _notifications = result.notificaciones;
        }

        _page = result.pagina;
        _hasMore = result.hayMas;
        _loading = false;
        _loadingMore = false;
      });

      final idInicial = widget.initialNotificationId;

      if (idInicial != null && !_notificacionInicialAbierta) {
        final indice = _notifications.indexWhere(
              (notificacion) => notificacion.id == idInicial,
        );

        if (indice >= 0) {
          final notificacion = _notifications[indice];

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _notificacionInicialAbierta) return;

            _notificacionInicialAbierta = true;
            _openNotification(notificacion);
          });
        }
      }

    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _loadingMore = false;

        if (!loadMore) {
          _error = error.toString();
        }
      });

      if (loadMore) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No se pudieron cargar más notificaciones.'),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () => unawaited(_loadNotifications(loadMore: true)),
            ),
          ),
        );
      }
    }
  }

  // =====================================================
  // HU-071: MARCAR COMO LEÍDA
  // =====================================================

  Future<void> _markAsRead(AnimapNotification notification) async {
    if (notification.leida || _markingAsRead.contains(notification.id)) {
      return;
    }

    setState(() {
      _markingAsRead.add(notification.id);
    });

    try {
      // Primero confirmar el cambio en PostgreSQL.
      await NotificationHistoryService.marcarComoLeida(notification.id);

      if (!mounted) return;

      final index = _notifications.indexWhere(
            (item) => item.id == notification.id,
      );

      if (index >= 0) {
        final actual = _notifications[index];

        // Actualizar el estado visual.
        setState(() {
          _notifications[index] = AnimapNotification(
            id: actual.id,
            titulo: actual.titulo,
            mensaje: actual.mensaje,
            tipo: actual.tipo,
            leida: true,
            fecha: actual.fecha,
            reporteId: actual.reporteId,
            avistamientoId: actual.avistamientoId,
            matchId: actual.matchId,
          );
        });
      }
    } catch (_) {
      if (!mounted) return;

      // Si falla el backend, la notificación
      // permanece como "Sin leer".
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No se pudo marcar la notificación como leída.'),
          action: SnackBarAction(
            label: 'Reintentar',
            onPressed: () {
              unawaited(_markAsRead(notification));
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingAsRead.remove(notification.id);
        });
      }
    }
  }

  // =====================================================
  // HU-072: NAVEGAR AL CONTENIDO RELACIONADO
  // =====================================================

  Future<void> _openRelatedContent(
      AnimapNotification notification,
      BuildContext sheetContext,
      ) async {
    try {
      if (notification.tipo == 'COINCIDENCIA_FOTOGRAFICA') {
        final session = SessionManager.instance;
        final generation = session.authenticatedSessionGeneration;
        final matchId = notification.matchId;
        if (!session.isAuthenticated || matchId == null) {
          throw const PhotoMatchesException(
            'El detalle privado de esta coincidencia no está disponible.',
          );
        }
        await PhotoMatchesService().detail(matchId);
        if (!mounted ||
            !sheetContext.mounted ||
            !session.isAuthenticated ||
            session.authenticatedSessionGeneration != generation) {
          return;
        }
        final navigator = Navigator.of(context);
        Navigator.of(sheetContext).pop();
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => PhotoMatchDetailPage(matchId: matchId),
          ),
        );
        return;
      }
      // Consultar el reporte o avistamiento en el backend.
      final contenido = await NotificationTargetService.buscarContenido(
        notification,
      );

      if (!mounted || !sheetContext.mounted) return;

      // El registro ya no aparece en el catálogo público.

      if (contenido == null) {
        await showDialog<void>(
          context: sheetContext,
          barrierDismissible: true,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF3F9568),
                    size: 28,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Contenido no disponible',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF344955),
                      ),
                    ),
                  ),
                ],
              ),
              content: const Text(
                'El reporte o avistamiento relacionado '
                    'con esta notificación ya no está disponible '
                    'para su consulta en AniMap.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFF53645B),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3F9568),
                  ),
                  child: const Text('Entendido'),
                ),
              ],
            );
          },
        );
        return;
      }

      // Convertir los datos al modelo que utiliza
      // actualmente el mapa de AniMap.
      final reporte = MapReport.fromJson(contenido);

      // Guardar el navegador antes de cerrar la ventana.
      final navigator = Navigator.of(context);

      // Cerrar la ventana de notificación.
      Navigator.of(sheetContext).pop();

      // Abrir la pantalla correspondiente.
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) {
            if (reporte.type == ReportType.sighting) {
              return SightingDetailPage(report: reporte);
            }

            return ReportDetailPage(report: reporte);
          },
        ),
      );
    } on PhotoMatchesException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on NotificationTargetException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ocurrió un error al abrir el contenido.'),
        ),
      );
    }
  }

  // =====================================================
  // HU-071: ABRIR NOTIFICACIÓN
  // =====================================================

  void _openNotification(AnimapNotification notification) {
    final esCoincidencia = notification.tipo == 'COINCIDENCIA_FOTOGRAFICA';
    final tieneContenido =
        esCoincidencia || NotificationTargetService.obtenerIdentificador(notification) != null;

    final esAvistamiento =
        notification.avistamientoId != null && notification.avistamientoId! > 0;

    bool abriendoContenido = false;

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return DraggableScrollableSheet(
                initialChildSize: 0.75,
                minChildSize: 0.45,
                maxChildSize: 0.95,
                expand: false,
                builder: (context, scrollController) {
                  return SafeArea(
                    top: false,
                    minimum: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),

                        // Indicador para deslizar.
                        Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD5DED8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Encabezado de notificación.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.notifications_active_outlined,
                                color: primaryGreen,
                                size: 28,
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Text(
                                  _getTypeName(notification.tipo),
                                  style: const TextStyle(
                                    color: primaryGreen,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: abriendoContenido
                                    ? null
                                    : () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        const Divider(height: 1, color: Color(0xFFE3EAE5)),

                        // Información desplazable.
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                            children: [
                              Text(
                                notification.titulo,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                  color: darkText,
                                ),
                              ),

                              const SizedBox(height: 20),

                              Text(
                                notification.mensaje,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.6,
                                  color: Color(0xFF53645B),
                                ),
                              ),

                              const SizedBox(height: 24),

                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time_outlined,
                                    size: 17,
                                    color: Colors.black45,
                                  ),

                                  const SizedBox(width: 8),

                                  Text(
                                    _formatDate(notification.fecha),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Acciones fijas en la parte inferior.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                          child: Column(
                            children: [
                              // HU-072:
                              // Mostrar únicamente cuando
                              // hay contenido relacionado.
                              if (tieneContenido) ...[
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: FilledButton.icon(
                                    onPressed: abriendoContenido
                                        ? null
                                        : () async {
                                      setSheetState(() {
                                        abriendoContenido = true;
                                      });

                                      try {
                                        await _openRelatedContent(
                                          notification,
                                          sheetContext,
                                        );
                                      } finally {
                                        if (sheetContext.mounted) {
                                          setSheetState(() {
                                            abriendoContenido = false;
                                          });
                                        }
                                      }
                                    },
                                    icon: abriendoContenido
                                        ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                        : Icon(
                                      esAvistamiento
                                          ? Icons.visibility_outlined
                                          : Icons.pets_outlined,
                                    ),
                                    label: Text(
                                      abriendoContenido
                                          ? 'Consultando...'
                                          : esCoincidencia
                                          ? 'Ver coincidencia'
                                          : esAvistamiento
                                          ? 'Ver avistamiento'
                                          : 'Ver reporte',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: primaryGreen,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),
                              ],

                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: OutlinedButton(
                                  onPressed: abriendoContenido
                                      ? null
                                      : () => Navigator.pop(sheetContext),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primaryGreen,
                                    side: const BorderSide(color: primaryGreen),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cerrar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );

    // HU-071: Mantener el marcado automático
    // como leída al abrir la notificación.
    if (!notification.leida) {
      unawaited(_markAsRead(notification));
    }
  }

  // =====================================================
  // FECHA Y TIPO
  // =====================================================

  String _formatDate(DateTime date) {
    final local = date.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year}'
        '  ${two(local.hour)}:${two(local.minute)}';
  }

  IconData _getIcon(String type) {
    switch (type.toUpperCase()) {
      case 'PERDIDA':
        return Icons.pets_outlined;

      case 'AVISTAMIENTO':
      case 'AVISTAMIENTO_VINCULADO':
        return Icons.visibility_outlined;

      case 'ENCONTRADO':
        return Icons.check_circle_outline;

      case 'COINCIDENCIA':
        return Icons.auto_awesome_outlined;

      default:
        return Icons.notifications_outlined;
    }
  }

  String _getTypeName(String type) {
    switch (type.toUpperCase()) {
      case 'PERDIDA':
        return 'Mascota perdida';

      case 'AVISTAMIENTO':
      case 'AVISTAMIENTO_VINCULADO':
        return 'Avistamiento';

      case 'ENCONTRADO':
        return 'Mascota encontrada';

      case 'COINCIDENCIA':
        return 'Posible coincidencia';

      default:
        return 'Aviso del sistema';
    }
  }

  // =====================================================
  // TARJETA DE NOTIFICACIÓN
  // =====================================================

  // Lista compacta: el contenido completo se consulta al abrir la fila.
  Widget _notificationCard(AnimapNotification notification) {
    final unread = !notification.leida;
    final marking = _markingAsRead.contains(notification.id);

    return Material(
      color: unread ? const Color(0xFFF0F8F2) : Colors.white,
      elevation: 1.2,
      shadowColor: const Color(0x1F344955),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: unread
              ? const Color(0xFF9CCFB0)
              : const Color(0xFFD9E3DC),
          width: 1.1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('notification-${notification.id}'),
        borderRadius: BorderRadius.circular(13),
        onTap: () => _openNotification(notification),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: unread
                      ? const Color(0xFFD7EDE0)
                      : const Color(0xFFF1F4F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getIcon(notification.tipo),
                  size: 21,
                  color: primaryGreen,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notification.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: darkText,
                        fontSize: 14,
                        fontWeight:
                        unread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.mensaje,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6A7B71),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _formatDate(notification.fecha),
                      style: const TextStyle(
                        color: Color(0xFF88958D),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (marking)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (unread)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: primaryGreen,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFFB1BDB5),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // HU-070: ACTUALIZACIÓN AUTOMÁTICA DEL HISTORIAL
  // =====================================================

  Future<void> _refreshAutomatically() async {
    if (_autoRefreshing || _loading || _loadingMore) {
      return;
    }

    _autoRefreshing = true;

    try {
      final resultado = await NotificationHistoryService.obtenerHistorial(
        pagina: 1,
      );

      if (!mounted) return;

      setState(() {
        if (_page <= 1) {
          // Si solo se ha cargado la primera página,
          // reemplazarla con los datos actualizados.
          _notifications = resultado.notificaciones;
          _page = resultado.pagina;
          _hasMore = resultado.hayMas;
        } else {
          // Conservar las notificaciones antiguas
          // cuando el usuario cargó más páginas.
          final idsNuevos = resultado.notificaciones.map((n) => n.id).toSet();

          _notifications = [
            ...resultado.notificaciones,
            ..._notifications.where((n) => !idsNuevos.contains(n.id)),
          ];
        }
      });
    } catch (_) {
      // Si falla la actualización automática,
      // conservar el historial existente.
      // El usuario puede actualizar manualmente.
    } finally {
      _autoRefreshing = false;
    }
  }

  // =====================================================
  // ESTADO VACÍO
  // =====================================================

  Widget _emptyView() {
    return RefreshIndicator(
      onRefresh: () => _loadNotifications(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 80,
                  color: Color(0xFF91CBA5),
                ),

                SizedBox(height: 18),

                Text(
                  'Aún no tienes notificaciones',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: 9),

                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 35),
                  child: Text(
                    'Cuando recibas alertas sobre mascotas '
                        'perdidas, avistamientos o avisos del '
                        'sistema, aparecerán aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // CONTENIDO
  // =====================================================

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryGreen),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 55,
                color: Colors.black45,
              ),

              const SizedBox(height: 12),

              const Text(
                'No se pudieron cargar las notificaciones',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),

              const SizedBox(height: 8),

              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),

              const SizedBox(height: 18),

              FilledButton.icon(
                onPressed: () => _loadNotifications(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return _emptyView();
    }

    return RefreshIndicator(
      onRefresh: () => _loadNotifications(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        itemCount: _notifications.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _notifications.length) {
            return Center(
              child: OutlinedButton.icon(
                onPressed: _loadingMore
                    ? null
                    : () => _loadNotifications(loadMore: true),
                icon: _loadingMore
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.expand_more),
                label: Text(_loadingMore ? 'Cargando...' : 'Cargar más'),
              ),
            );
          }

          return _notificationCard(_notifications[index]);
        },
      ),
    );
  }

  // =====================================================
  // INTERFAZ PRINCIPAL
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications
        .where((notification) => !notification.leida)
        .length;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Notificaciones',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFDFF3E8),
        foregroundColor: darkText,
        actions: [
          IconButton(
            tooltip: 'Actualizar notificaciones',
            onPressed: _loading ? null : () => _loadNotifications(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _loading
                        ? 'Cargando notificaciones...'
                        : unreadCount == 0
                        ? 'Estás al día'
                        : '$unreadCount sin leer',
                    style: const TextStyle(
                      color: Color(0xFF607369),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!_loading)
                  Text(
                    '${_notifications.length} notificaciones',
                    style: const TextStyle(
                      color: Color(0xFF829389),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }
}

