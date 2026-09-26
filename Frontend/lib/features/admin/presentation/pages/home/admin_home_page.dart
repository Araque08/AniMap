import 'package:flutter/material.dart';

import '../../../../auth/data/session_manager.dart';
import '../../../../auth/presentation/session_navigation.dart';
import '../faq/admin_faq_page.dart';
import '../users/admin_users_page.dart';

class AdminHomePage extends StatelessWidget {
  final SessionManager? sessionManager;

  const AdminHomePage({
    super.key,
    this.sessionManager,
  });

  // =========================================================
  // COLORES PRINCIPALES
  // =========================================================

  static const Color green = Color(0xFF3F9568);
  static const Color darkGreen = Color(0xFF2F7651);
  static const Color lightGreen = Color(0xFFEAF5EF);

  static const Color background = Color(0xFFF5F8F6);

  static const Color textPrimary = Color(0xFF26352E);
  static const Color textSecondary = Color(0xFF718078);

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            30,
          ),
          children: [

            // =================================================
            // CABECERA
            // =================================================

            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Panel administrativo',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Administración de AniMap',
                        style: TextStyle(
                          fontSize: 14,
                          color: textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // BOTÓN CERRAR SESIÓN
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () {
                      confirmLogoutAndNavigate(
                        context,
                        sessionManager: sessionManager,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: const Color(0xFFE5ECE8),
                        ),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFB95050),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            // =================================================
            // TARJETA PRINCIPAL
            // =================================================

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    green,
                    darkGreen,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: green.withValues(alpha: 0.20),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Row(
                children: [

                  // ICONO
                  _HeaderIcon(),

                  SizedBox(width: 18),

                  // TEXTO
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AniMap Admin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          'Gestiona las principales funciones de la plataforma desde un solo lugar.',
                          style: TextStyle(
                            color: Color(0xFFE9F5EE),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // =================================================
            // TÍTULO SECCIÓN
            // =================================================

            const Text(
              'Gestión',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              'Selecciona una sección para administrarla.',
              style: TextStyle(
                fontSize: 14,
                color: textSecondary,
              ),
            ),

            const SizedBox(height: 18),

            // =================================================
            // PREGUNTAS FRECUENTES
            // =================================================

            _AdminLink(
              title: 'Preguntas frecuentes',
              subtitle:
              'Administra el contenido y las categorías del centro de ayuda.',
              icon: Icons.help_outline_rounded,
              iconBackground: lightGreen,
              iconColor: green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminFaqPage(),
                  ),
                );
              },
            ),

            const SizedBox(height: 14),

            // =================================================
            // GESTIÓN DE USUARIOS
            // =================================================
            //
            // Por ahora esta tarjeta es únicamente visual.
            // Más adelante se conectará con la página de
            // administración de usuarios.
            // =================================================

            _AdminLink(
              title: 'Gestión de usuarios',
              subtitle:
              'Consulta y administra los usuarios registrados en AniMap.',
              icon: Icons.people_alt_outlined,
              iconBackground:
              const Color(0xFFEAF1F8),
              iconColor:
              const Color(0xFF4779A8),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                    const AdminUsersPage(),
                  ),
                );
              },
            ),

            const SizedBox(height: 14),

            // =================================================
            // REPORTES
            // =================================================
            //
            // También se deja preparada visualmente.
            // Después se conectará con su página correspondiente.
            // =================================================

            _AdminLink(
              title: 'Reportes',
              subtitle:
              'Consulta los reportes y novedades registradas en la plataforma.',
              icon: Icons.flag_outlined,
              iconBackground: const Color(0xFFFFF2E4),
              iconColor: const Color(0xFFD68738),
              status: 'Próximamente',
              onTap: null,
            ),

            const SizedBox(height: 30),

            // =================================================
            // TEXTO INFERIOR
            // =================================================

            const Center(
              child: Text(
                'AniMap • Panel administrativo',
                style: TextStyle(
                  color: Color(0xFFA0ACA5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// ICONO DEL ENCABEZADO
// =============================================================

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.20),
        ),
      ),
      child: const Icon(
        Icons.admin_panel_settings_rounded,
        color: Colors.white,
        size: 31,
      ),
    );
  }
}

// =============================================================
// TARJETA DE OPCIÓN ADMINISTRATIVA
// =============================================================

class _AdminLink extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  final Color iconBackground;
  final Color iconColor;

  final String? status;

  final VoidCallback? onTap;

  const _AdminLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.onTap,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        borderRadius: BorderRadius.circular(21),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: const Color(0xFFE4EBE7),
            ),
          ),
          child: Row(
            children: [

              // =================================================
              // ICONO
              // =================================================

              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 27,
                ),
              ),

              const SizedBox(width: 15),

              // =================================================
              // INFORMACIÓN
              // =================================================

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AdminHomePage.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),

                        if (status != null)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F4F2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status!,
                              style: const TextStyle(
                                color: Color(0xFF7D8982),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      subtitle,
                      style: TextStyle(
                        color: enabled
                            ? AdminHomePage.textSecondary
                            : const Color(0xFF929D97),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // =================================================
              // FLECHA / BLOQUEADO
              // =================================================

              Icon(
                enabled
                    ? Icons.chevron_right_rounded
                    : Icons.lock_outline_rounded,
                color: enabled
                    ? const Color(0xFF8B9891)
                    : const Color(0xFFB2BBB6),
                size: enabled ? 26 : 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
