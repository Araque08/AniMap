import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/data/session_manager.dart';
import '../features/auth/presentation/session_navigation.dart';
import '../features/notifications/data/notification_history_service.dart';

class _AniMapMenuStyle {
  static const green = Color(0xFF3F9568);
  static const paleGreen = Color(0xFFE2F3E9);
  static const background = Color(0xFFFAFCFA);
  static const text = Color(0xFF344955);
  static const secondary = Color(0xFF718078);
  static const divider = Color(0xFFE5ECE7);
}

class _MenuLogo extends StatelessWidget {
  const _MenuLogo({this.size = 39});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_animap.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: _AniMapMenuStyle.green,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.pets, color: Colors.white, size: size * 0.58),
      ),
    );
  }
}

/// Barra superior compatible con el widget original.
class TopMenuAnimap extends StatefulWidget {
  const TopMenuAnimap({super.key, this.onNotificationTap});

  final VoidCallback? onNotificationTap;

  @override
  State<TopMenuAnimap> createState() => _TopMenuAnimapState();
}

class _TopMenuAnimapState extends State<TopMenuAnimap>
    with WidgetsBindingObserver {
  int _unreadCount = 0;
  bool _refreshingCount = false;
  Timer? _badgeTimer;
  int? _sessionGeneration;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionGeneration =
        SessionManager.instance.authenticatedSessionGeneration;
    _updateUnreadCount();
    _badgeTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) => _updateUnreadCount(),
    );
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateUnreadCount();
    }
  }

  Future<void> _updateUnreadCount() async {
    if (_refreshingCount || !mounted) return;
    _refreshingCount = true;
    final generation =
        SessionManager.instance.authenticatedSessionGeneration;

    try {
      var page = 1;
      var unread = 0;
      final seen = <int>{};

      // El servicio ofrece historial paginado. Se consultan todas las
      // páginas para que el distintivo represente el total sin leer.
      while (true) {
        final history = await NotificationHistoryService.obtenerHistorial(
          pagina: page,
        );
        if (!mounted ||
            generation !=
                SessionManager.instance.authenticatedSessionGeneration) {
          return;
        }

        for (final notification in history.notificaciones) {
          if (seen.add(notification.id) && !notification.leida) unread++;
        }
        if (!history.hayMas || history.notificaciones.isEmpty) break;
        page++;
      }

      if (mounted) setState(() => _unreadCount = unread);
    } catch (_) {
      // Mantener el último contador si hay un problema de red.
    } finally {
      _refreshingCount = false;
    }
  }

  Future<void> _openNotifications() async {
    if (widget.onNotificationTap != null) {
      widget.onNotificationTap!();
      return;
    }
    await Navigator.pushNamed(context, '/notifications');
    if (mounted) await _updateUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    final statusHeight = MediaQuery.paddingOf(context).top;
    final currentGeneration =
        SessionManager.instance.authenticatedSessionGeneration;
    if (currentGeneration != _sessionGeneration) {
      _sessionGeneration = currentGeneration;
      _unreadCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateUnreadCount();
      });
    }

    return Container(
      height: statusHeight + 66,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(10, statusHeight + 5, 10, 5),
      decoration: const BoxDecoration(
        color: _AniMapMenuStyle.paleGreen,
        border: Border(
          bottom: BorderSide(color: _AniMapMenuStyle.divider),
        ),
      ),
      child: Row(
        children: [
          Builder(
            builder: (drawerContext) => IconButton(
              tooltip: 'Abrir menú',
              onPressed: () => Scaffold.of(drawerContext).openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: _AniMapMenuStyle.text),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _MenuLogo(size: 38),
                const SizedBox(width: 7),
                const Flexible(
                  child: Text(
                    'AniMap',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: _AniMapMenuStyle.text,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _unreadCount == 0
                ? 'Notificaciones'
                : 'Notificaciones: $_unreadCount sin leer',
            onPressed: _openNotifications,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: _AniMapMenuStyle.text,
                  size: 27,
                ),
                if (_unreadCount > 0)
                  Positioned(
                    right: -9,
                    top: -8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE25A5A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _AniMapMenuStyle.paleGreen,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
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
  }
}

/// Menú lateral sobrio con las rutas y el cierre de sesión originales.
class AniMapSideMenu extends StatelessWidget {
  const AniMapSideMenu({super.key, this.sessionManager});

  final SessionManager? sessionManager;

  void _goTo(BuildContext context, String routeName) {
    Navigator.pop(context);
    Navigator.pushReplacementNamed(context, routeName);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Drawer(
      width: width < 330 ? width * 0.87 : 290,
      backgroundColor: _AniMapMenuStyle.background,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 18),
              child: Row(
                children: [
                  const _MenuLogo(size: 43),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'AniMap',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _AniMapMenuStyle.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar menú',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: _AniMapMenuStyle.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _AniMapMenuStyle.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                children: [
                  _SimpleMenuItem(
                    icon: Icons.search_rounded,
                    text: 'Mascotas perdidas',
                    onTap: () => _goTo(context, '/home'),
                  ),
                  _SimpleMenuItem(
                    icon: Icons.pets_outlined,
                    text: 'Mis mascotas',
                    onTap: () => _goTo(context, '/pet-list'),
                  ),
                  const SizedBox(height: 8),
                  _SimpleMenuItem(
                    icon: Icons.add_circle_outline_rounded,
                    text: 'Crear reporte',
                    emphasized: true,
                    onTap: () => _goTo(context, '/create-report'),
                  ),
                  const SizedBox(height: 8),
                  _SimpleMenuItem(
                    icon: Icons.help_outline_rounded,
                    text: 'Preguntas frecuentes',
                    onTap: () => _goTo(context, '/faqs'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _AniMapMenuStyle.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: _SimpleMenuItem(
                icon: Icons.logout_rounded,
                text: 'Cerrar sesión',
                destructive: true,
                onTap: () => confirmLogoutAndNavigate(
                  context,
                  sessionManager: sessionManager,
                  closeDrawer: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleMenuItem extends StatelessWidget {
  const _SimpleMenuItem({
    required this.icon,
    required this.text,
    required this.onTap,
    this.emphasized = false,
    this.destructive = false,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool emphasized;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFAD4B4B)
        : emphasized
        ? _AniMapMenuStyle.green
        : _AniMapMenuStyle.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: emphasized ? _AniMapMenuStyle.paleGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight:
                      emphasized ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

