import 'package:flutter/material.dart';

import '../faq/admin_faq_page.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({
    super.key,
    this.onUsuariosTap,
    this.onReportesTap,
    this.onFaqTap,
    this.onNotificacionesTap,
    this.onBitacoraTap,
  });

  final VoidCallback? onUsuariosTap;
  final VoidCallback? onReportesTap;
  final VoidCallback? onFaqTap;
  final VoidCallback? onNotificacionesTap;
  final VoidCallback? onBitacoraTap;

  // Colores que ya venimos utilizando en AniMap
  static const Color backgroundColor = Color(0xFFF7FAF8);
  static const Color lightGreen = Color(0xFFDFF3E8);
  static const Color accentGreen = Color(0xFF3F9568);
  static const Color darkGreen = Color(0xFF2F7452);
  static const Color darkText = Color(0xFF344955);
  static const Color secondaryText = Color(0xFF73828C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeCard(),

                    const SizedBox(height: 28),

                    const Text(
                      'Administración',
                      style: TextStyle(
                        color: darkText,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Gestiona las principales funciones administrativas de AniMap.',
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 20),

                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.05,
                      children: [
                        _AdminOptionCard(
                          title: 'Preguntas\nfrecuentes',
                          subtitle: 'Gestionar FAQ',
                          icon: Icons.help_outline_rounded,
                          onTap: onFaqTap ??
                                  () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminFaqPage(),
                                  ),
                                );
                              },
                        ),
                        _AdminOptionCard(
                          title: 'Reportes',
                          subtitle: 'Moderar contenido',
                          icon: Icons.pets_outlined,
                          onTap: onReportesTap,
                        ),
                        _AdminOptionCard(
                          title: 'Preguntas\nfrecuentes',
                          subtitle: 'Gestionar FAQ',
                          icon: Icons.help_outline_rounded,
                          onTap: onFaqTap,
                        ),
                        _AdminOptionCard(
                          title: 'Notificaciones',
                          subtitle: 'Enviar avisos',
                          icon: Icons.notifications_none_rounded,
                          onTap: onNotificacionesTap,
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    _buildAuditCard(),

                    const SizedBox(height: 26),

                    _buildInfoBox(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // MENÚ SUPERIOR
  // ---------------------------------------------------------

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE8EEEA),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: lightGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: accentGreen,
              size: 27,
            ),
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AniMap',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Panel administrativo',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),

          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F7F4),
              borderRadius: BorderRadius.circular(13),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: darkText,
                size: 23,
              ),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // TARJETA PRINCIPAL
  // ---------------------------------------------------------

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: accentGreen,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: accentGreen.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Colors.white,
              size: 34,
            ),
          ),

          const SizedBox(width: 17),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, Administrador',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Controla y administra las funciones principales de AniMap.',
                  style: TextStyle(
                    color: Color(0xFFEAF6F0),
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // BITÁCORA
  // ---------------------------------------------------------

  Widget _buildAuditCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onBitacoraTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE6ECE8),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: accentGreen,
                  size: 27,
                ),
              ),

              const SizedBox(width: 15),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bitácora administrativa',
                      style: TextStyle(
                        color: darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Consulta las acciones realizadas en el sistema.',
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFF9AA7A0),
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // INFORMACIÓN
  // ---------------------------------------------------------

  Widget _buildInfoBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: lightGreen.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: accentGreen,
            size: 23,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Las opciones de esta sección están disponibles únicamente '
                  'para usuarios con permisos de administrador.',
              style: TextStyle(
                color: darkText,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// TARJETA REUTILIZABLE DEL MENÚ ADMIN
// =============================================================

class _AdminOptionCard extends StatelessWidget {
  const _AdminOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  static const Color lightGreen = Color(0xFFDFF3E8);
  static const Color accentGreen = Color(0xFF3F9568);
  static const Color darkText = Color(0xFF344955);
  static const Color secondaryText = Color(0xFF73828C);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFE6ECE8),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: accentGreen,
                  size: 25,
                ),
              ),

              const Spacer(),

              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: darkText,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: secondaryText,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}