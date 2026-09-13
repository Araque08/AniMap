import 'package:flutter/material.dart';

class TopMenuAnimap extends StatelessWidget {
  const TopMenuAnimap({
    super.key,
    this.onNotificationTap,
  });

  final VoidCallback? onNotificationTap;

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF2F8F5B);
  static const Color lightGreen = Color(0xFFEAF7EF);
  static const Color darkText = Color(0xFF1C2B24);
  static const Color borderColor = Color(0xFFE3EAE6);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 82,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(
              color: borderColor,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 18,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // BOTÓN MENÚ
            Builder(
              builder: (context) {
                return _TopIconButton(
                  icon: Icons.menu_rounded,
                  onTap: () {
                    Scaffold.of(context).openDrawer();
                  },
                );
              },
            ),

            const Spacer(),

            // LOGO CENTRAL
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: lightGreen,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: primaryGreen.withOpacity(.18),
                    ),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo_animap.png',
                      fit: BoxFit.contain,
                      errorBuilder: (
                          context,
                          error,
                          stackTrace,
                          ) {
                        return const Center(
                          child: Icon(
                            Icons.pets_rounded,
                            color: darkGreen,
                            size: 28,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(width: 9),

                const Text(
                  'AniMap',
                  style: TextStyle(
                    fontSize: 25,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: darkText,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // NOTIFICACIONES
            _NotificationButton(
              onTap:
              onNotificationTap ??
                      () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(
                              Icons.notifications_none_rounded,
                              color: Colors.white,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Aquí irán las notificaciones.',
                            ),
                          ],
                        ),
                        backgroundColor: darkGreen,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    );
                  },
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================
// BOTÓN SUPERIOR
// ======================================================

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  static const Color lightGreen = Color(0xFFEAF7EF);
  static const Color darkGreen = Color(0xFF2F8F5B);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: lightGreen,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            color: darkGreen,
            size: 25,
          ),
        ),
      ),
    );
  }
}

// ======================================================
// NOTIFICACIONES
// ======================================================

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  static const Color lightGreen = Color(0xFFEAF7EF);
  static const Color darkGreen = Color(0xFF2F8F5B);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: lightGreen,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: onTap,
            child: const SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                Icons.notifications_none_rounded,
                color: darkGreen,
                size: 25,
              ),
            ),
          ),
        ),

        // PEQUEÑO INDICADOR VISUAL
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6258),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ======================================================
// MENÚ LATERAL
// ======================================================

class AniMapSideMenu extends StatelessWidget {
  const AniMapSideMenu({
    super.key,
  });

  static const Color background = Color(0xFFF8FAF9);
  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF2F8F5B);
  static const Color lightGreen = Color(0xFFEAF7EF);
  static const Color darkText = Color(0xFF1C2B24);
  static const Color secondaryText = Color(0xFF718078);
  static const Color borderColor = Color(0xFFE3EAE6);

  void _goTo(
      BuildContext context,
      String routeName,
      ) {
    Navigator.pop(context);

    Navigator.pushReplacementNamed(
      context,
      routeName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute =
        ModalRoute.of(context)?.settings.name;

    return Drawer(
      width: 300,
      elevation: 0,
      backgroundColor: background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ============================================
            // CABECERA
            // ============================================

            Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                22,
                16,
                18,
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: lightGreen,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryGreen.withOpacity(.20),
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo_animap.png',
                        fit: BoxFit.contain,
                        errorBuilder: (
                            context,
                            error,
                            stackTrace,
                            ) {
                          return const Icon(
                            Icons.pets_rounded,
                            color: darkGreen,
                            size: 30,
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AniMap',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: darkText,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Encuentra. Reporta. Ayuda.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.close_rounded,
                          size: 22,
                          color: secondaryText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(
              height: 1,
              thickness: 1,
              color: borderColor,
            ),

            const SizedBox(height: 18),

            // ============================================
            // TEXTO DE SECCIÓN
            // ============================================

            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 22,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'NAVEGACIÓN',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: secondaryText,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ============================================
            // OPCIONES
            // ============================================

            _SideMenuItem(
              icon: Icons.pets_outlined,
              selectedIcon: Icons.pets_rounded,
              text: 'Mascotas perdidas',
              isSelected: currentRoute == '/home',
              onTap: () {
                _goTo(
                  context,
                  '/home',
                );
              },
            ),

            _SideMenuItem(
              icon: Icons.favorite_border_rounded,
              selectedIcon: Icons.favorite_rounded,
              text: 'Mis mascotas',
              isSelected: currentRoute == '/pet-list',
              onTap: () {
                _goTo(
                  context,
                  '/pet-list',
                );
              },
            ),

            _SideMenuItem(
              icon: Icons.add_circle_outline_rounded,
              selectedIcon: Icons.add_circle_rounded,
              text: 'Crear reporte',
              isSelected:
              currentRoute == '/create-report',
              onTap: () {
                _goTo(
                  context,
                  '/create-report',
                );
              },
            ),

            _SideMenuItem(
              icon: Icons.help_outline_rounded,
              selectedIcon:
              Icons.help_rounded,
              text: 'Preguntas frecuentes',
              isSelected: currentRoute == '/faqs',
              onTap: () {
                _goTo(
                  context,
                  '/faqs',
                );
              },
            ),

            const Spacer(),

            // ============================================
            // CERRAR SESIÓN
            // ============================================

            Padding(
              padding: const EdgeInsets.fromLTRB(
                14,
                8,
                14,
                18,
              ),
              child: Material(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                            ),
                            SizedBox(width: 10),
                            Text('Sesión cerrada.'),
                          ],
                        ),
                        backgroundColor:
                        Colors.red.shade700,
                        behavior:
                        SnackBarBehavior.floating,
                        shape:
                        RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(14),
                        ),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 22,
                          color: Color(0xFFD84A4A),
                        ),
                        SizedBox(width: 14),
                        Text(
                          'Cerrar sesión',
                          style: TextStyle(
                            color: Color(0xFFD84A4A),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================
// ELEMENTO DEL MENÚ LATERAL
// ======================================================

class _SideMenuItem extends StatelessWidget {
  const _SideMenuItem({
    required this.icon,
    required this.selectedIcon,
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF2F8F5B);
  static const Color lightGreen = Color(0xFFEAF7EF);
  static const Color darkText = Color(0xFF1C2B24);
  static const Color secondaryText = Color(0xFF718078);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 3,
      ),
      child: Material(
        color: isSelected
            ? lightGreen
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor:
          primaryGreen.withOpacity(.08),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration:
                  const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white
                        : const Color(0xFFF0F4F2),
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSelected
                        ? selectedIcon
                        : icon,
                    size: 21,
                    color: isSelected
                        ? darkGreen
                        : secondaryText,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isSelected
                          ? darkGreen
                          : darkText,
                    ),
                  ),
                ),

                AnimatedOpacity(
                  opacity:
                  isSelected ? 1 : 0,
                  duration:
                  const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: darkGreen,
                    size: 20,
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