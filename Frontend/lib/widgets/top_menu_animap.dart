import 'package:flutter/material.dart';

import '../features/auth/data/session_manager.dart';
import '../features/auth/presentation/session_navigation.dart';

class TopMenuAnimap extends StatelessWidget {
  const TopMenuAnimap({super.key, this.onNotificationTap});

  final VoidCallback? onNotificationTap;

  static const Color lightGreen = Color(0xFFDFF3E8);
  static const Color darkText = Color(0xFF344955);
  static const Color accentGreen = Color(0xFF3F9568);

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      height: statusBarHeight + 92,
      color: lightGreen,
      padding: EdgeInsets.only(
        top: statusBarHeight + 8,
        left: 12,
        right: 12,
        bottom: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Builder(
            builder: (context) {
              return IconButton(
                onPressed: () {
                  Scaffold.of(context).openDrawer();
                },
                icon: const Icon(Icons.menu, size: 30, color: Colors.black87),
              );
            },
          ),

          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo_animap.png',
                    height: 46,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: accentGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.pets,
                          color: Colors.white,
                          size: 26,
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 8),

                  const Text(
                    'AniMap',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: darkText,
                    ),
                  ),
                ],
              ),
            ),
          ),

          IconButton(
            onPressed:
                onNotificationTap ??
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Aquí irán las notificaciones.'),
                    ),
                  );
                },
            icon: const Icon(
              Icons.notifications,
              size: 27,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class AniMapSideMenu extends StatelessWidget {
  final SessionManager? sessionManager;

  const AniMapSideMenu({super.key, this.sessionManager});

  static const Color background = Color(0xFFF8FAF6);
  static const Color divider = Color(0xFFCFE4D7);
  static const Color darkText = Color(0xFF344955);

  void _goTo(BuildContext context, String routeName) {
    Navigator.pop(context);
    Navigator.pushReplacementNamed(context, routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: background,
      width: 270,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/logo_animap.png',
                    height: 42,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3F9568),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.pets,
                          color: Colors.white,
                          size: 24,
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 8),

                  const Text(
                    'AniMap',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: darkText,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 62),

            _SideMenuItem(
              text: 'Mascotas Perdidas',
              onTap: () {
                _goTo(context, '/home');
              },
            ),

            _SideMenuItem(
              text: 'Mis Mascotas',
              onTap: () {
                _goTo(context, '/pet-list');
              },
            ),

            _SideMenuItem(
              text: 'Preguntas Frecuentes',
              onTap: () {
                _goTo(context, '/faqs');
              },
            ),

            _SideMenuItem(
              text: 'Cerrar sesión',
              onTap: () => confirmLogoutAndNavigate(
                context,
                sessionManager: sessionManager,
                closeDrawer: true,
              ),
            ),

            _SideMenuItem(
              text: 'Crear reporte',
              onTap: () {
                _goTo(context, '/create-report');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SideMenuItem extends StatelessWidget {
  const _SideMenuItem({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(
          height: 1,
          thickness: 1,
          color: AniMapSideMenu.divider,
          indent: 20,
          endIndent: 20,
        ),

        InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 62,
            width: double.infinity,
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

//Esto se coloca dentro de "return Scaffold(" para mostrar las opciones del menud e hambrurguesa

/* drawer: const AniMapSideMenu(),*/

// y este drontro de childen de primeras para que lo muestre en el tope

/*const TopMenuAnimap(),*/
