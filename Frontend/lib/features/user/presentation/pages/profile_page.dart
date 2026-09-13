import 'package:flutter/material.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../../auth/data/auth_service.dart';
import '../../data/profile_service.dart';
import 'profile_options_pages.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.onMenu,
    this.onNotifications,
    this.onLogout,
    this.onDeleteAccount,
    this.onHome,
    this.onPets,
    this.onProfile,
  });

  final VoidCallback? onMenu;
  final VoidCallback? onNotifications;
  final VoidCallback? onLogout;
  final VoidCallback? onDeleteAccount;

  final VoidCallback? onHome;
  final VoidCallback? onPets;
  final VoidCallback? onProfile;

  // ============================================================
  // COLORES ANIMAP
  // ============================================================

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);
  static const Color darkerGreen = Color(0xFF267A4F);

  static const Color lightGreen = Color(0xFFD9F0E2);
  static const Color veryLightGreen = Color(0xFFF0F8F3);

  static const Color background = Color(0xFFF7F9F8);

  static const Color textDark = Color(0xFF172126);
  static const Color textGrey = Color(0xFF697378);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();

    _profileFuture = ProfileService.obtenerPerfil();
  }

  void _reloadProfile() {
    if (!mounted) return;

    setState(() {
      _profileFuture = ProfileService.obtenerPerfil();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        // ========================================================
        // CARGANDO
        // ========================================================

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildStatusScaffold(
            child: const CircularProgressIndicator(
              color: ProfilePage.darkGreen,
            ),
          );
        }

        // ========================================================
        // ERROR
        // ========================================================

        if (snapshot.hasError || snapshot.data == null) {
          final message = snapshot.error is ProfileException
              ? (snapshot.error as ProfileException).message
              : 'No se pudo cargar el perfil';

          return _buildStatusScaffold(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 52,
                  color: ProfilePage.darkGreen,
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ProfilePage.textDark,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _reloadProfile,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ProfilePage.darkGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return _buildProfile(
          context,
          snapshot.data!,
        );
      },
    );
  }

  // ============================================================
  // SCAFFOLD PARA CARGA / ERROR
  // ============================================================

  Widget _buildStatusScaffold({
    required Widget child,
  }) {
    return Scaffold(
      backgroundColor: ProfilePage.background,
      drawer: const AniMapSideMenu(),
      body: SafeArea(
        child: Column(
          children: [
            const TopMenuAnimap(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuAnimap(
        currentIndex: 2,
      ),
    );
  }

  // ============================================================
  // PERFIL
  // ============================================================

  Widget _buildProfile(
      BuildContext context,
      Map<String, dynamic> profile,
      ) {
    final String userName =
        profile['nombre']?.toString().trim() ?? 'Usuario';

    final String userEmail =
        profile['email']?.toString().trim() ?? '';

    final String? profilePhotoUrl =
    profile['foto_url']?.toString();

    final ImageProvider? avatarImage =
    profilePhotoUrl != null &&
        profilePhotoUrl.trim().isNotEmpty
        ? NetworkImage(profilePhotoUrl)
        : null;

    return Scaffold(
      backgroundColor: ProfilePage.background,

      drawer: const AniMapSideMenu(),

      body: SafeArea(
        child: Column(
          children: [
            // ====================================================
            // MENÚ SUPERIOR EXISTENTE DE ANIMAP
            // ====================================================

            const TopMenuAnimap(),

            // ====================================================
            // CONTENIDO
            // ====================================================

            Expanded(
              child: RefreshIndicator(
                color: ProfilePage.darkGreen,
                onRefresh: () async {
                  _reloadProfile();

                  try {
                    await _profileFuture;
                  } catch (_) {}
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    28,
                  ),
                  child: Column(
                    children: [
                      // ==========================================
                      // TARJETA PRINCIPAL
                      // ==========================================

                      _ProfileHeaderCard(
                        userName: userName,
                        email: userEmail,
                        avatarImage: avatarImage,
                      ),

                      const SizedBox(height: 24),

                      // ==========================================
                      // INFORMACIÓN PERSONAL
                      // ==========================================

                      _ProfileOptionCard(
                        icon: Icons.person_rounded,
                        title: 'Información personal',
                        subtitle:
                        'Edita tus datos y foto de perfil',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PersonalInfoPage(
                                profile: profile,
                                onUpdated: _reloadProfile,
                              ),
                            ),
                          );

                          _reloadProfile();
                        },
                      ),

                      const SizedBox(height: 12),

                      // ==========================================
                      // SESIONES ACTIVAS
                      // ==========================================

                      _ProfileOptionCard(
                        icon: Icons.lock_rounded,
                        title: 'Sesiones activas',
                        subtitle:
                        'Revisa y administra tus sesiones',
                        onTap: () {
                        },
                      ),

                      const SizedBox(height: 12),

                      // ==========================================
                      // NOTIFICACIONES
                      // ==========================================

                      _ProfileOptionCard(
                        icon: Icons.notifications_rounded,
                        title: 'Preferencias de notificación',
                        subtitle:
                        'Configura las alertas que quieres recibir',
                        onTap: () {
                        },
                      ),

                      const SizedBox(height: 12),

                      // ==========================================
                      // CERRAR SESIÓN
                      // ==========================================

                      _ProfileOptionCard(
                        icon: Icons.logout_rounded,
                        title: 'Cerrar sesión',
                        subtitle:
                        'Salir de tu cuenta de AniMap',
                        onTap: () {
                          _showConfirmDialog(
                            context: context,
                            title: 'Cerrar sesión',
                            message:
                            '¿Estás seguro de que deseas cerrar tu sesión?',
                            confirmText: 'Cerrar sesión',
                            onConfirm: () {
                              Navigator.pop(context);

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Sesión cerrada correctamente',
                                  ),
                                ),
                              );

                              AuthService.clearAccessToken();

                              if (widget.onLogout != null) {
                                widget.onLogout!();
                              } else {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/login',
                                      (_) => false,
                                );
                              }
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // ==========================================
                      // ELIMINAR CUENTA
                      // ==========================================

                      _ProfileOptionCard(
                        icon: Icons.person_remove_rounded,
                        title: 'Eliminar cuenta',
                        subtitle:
                        'Eliminar permanentemente tu cuenta',
                        isDanger: true,
                        onTap: () {
                          _showConfirmDialog(
                            context: context,
                            title: 'Eliminar cuenta',
                            message:
                            'Esta acción eliminará tu cuenta y la información asociada. ¿Deseas continuar?',
                            confirmText: 'Eliminar',
                            isDanger: true,
                            onConfirm: () {
                              Navigator.pop(context);

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Solicitud de eliminación de cuenta realizada',
                                  ),
                                ),
                              );

                              if (widget.onDeleteAccount != null) {
                                widget.onDeleteAccount!();
                              }
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 30),

                      // ==========================================
                      // MARCA INFERIOR
                      // ==========================================

                      const _AniMapFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: const BottomMenuAnimap(
        currentIndex: 2,
      ),
    );
  }
}

// ============================================================================
// TARJETA PRINCIPAL DEL PERFIL
// ============================================================================

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.userName,
    required this.email,
    required this.avatarImage,
  });

  final String userName;
  final String email;
  final ImageProvider? avatarImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        minHeight: 310,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            // ====================================================
            // FONDO CLARO
            // ====================================================

            Positioned.fill(
              child: Container(
                color: ProfilePage.veryLightGreen,
              ),
            ),

            // ====================================================
            // ONDA SUPERIOR
            // ====================================================

            Positioned(
              top: -45,
              right: -50,
              child: Container(
                width: 300,
                height: 160,
                decoration: BoxDecoration(
                  color:
                  ProfilePage.primaryGreen.withOpacity(0.17),
                  borderRadius: BorderRadius.circular(100),
                ),
                transform: Matrix4.rotationZ(-0.20),
              ),
            ),

            // ====================================================
            // ONDA INFERIOR
            // ====================================================

            Positioned(
              bottom: -70,
              left: -100,
              child: Container(
                width: 320,
                height: 190,
                decoration: BoxDecoration(
                  color:
                  ProfilePage.primaryGreen.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(120),
                ),
                transform: Matrix4.rotationZ(0.24),
              ),
            ),

            // ====================================================
            // HUELLAS DECORATIVAS
            // ====================================================

            Positioned(
              top: 88,
              left: 34,
              child: Transform.rotate(
                angle: -0.25,
                child: Icon(
                  Icons.pets_rounded,
                  size: 42,
                  color:
                  ProfilePage.primaryGreen.withOpacity(0.24),
                ),
              ),
            ),

            Positioned(
              right: 34,
              bottom: 80,
              child: Transform.rotate(
                angle: 0.22,
                child: Icon(
                  Icons.pets_rounded,
                  size: 42,
                  color:
                  ProfilePage.primaryGreen.withOpacity(0.24),
                ),
              ),
            ),

            // ====================================================
            // INFORMACIÓN CENTRAL
            // ====================================================

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 26,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 2),

                    // ==============================================
                    // FOTO
                    // ==============================================

                    Container(
                      width: 154,
                      height: 154,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: ProfilePage.darkGreen,
                          width: 5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ProfilePage.darkGreen
                                .withOpacity(0.18),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: ClipOval(
                          child: avatarImage != null
                              ? Image(
                            image: avatarImage!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder:
                                (
                                context,
                                error,
                                stackTrace,
                                ) {
                              return const _DefaultAvatar();
                            },
                          )
                              : const _DefaultAvatar(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 17),

                    // ==============================================
                    // NOMBRE
                    // ==============================================

                    Text(
                      userName.isEmpty ? 'Usuario' : userName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfilePage.textDark,
                        fontSize: 23,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    // ==============================================
                    // CORREO
                    // ==============================================

                    if (email.isNotEmpty)
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ProfilePage.textGrey,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// AVATAR POR DEFECTO
// ============================================================================

class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ProfilePage.lightGreen,
      alignment: Alignment.center,
      child: const Icon(
        Icons.person_rounded,
        size: 82,
        color: ProfilePage.darkGreen,
      ),
    );
  }
}

// ============================================================================
// TARJETA DE OPCIÓN
// ============================================================================

class _ProfileOptionCard extends StatelessWidget {
  const _ProfileOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = isDanger
        ? const Color(0xFFC73A3A)
        : ProfilePage.darkGreen;

    final Color iconBackground = isDanger
        ? const Color(0xFFFDECEC)
        : ProfilePage.veryLightGreen;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor:
        ProfilePage.primaryGreen.withOpacity(0.08),
        highlightColor:
        ProfilePage.primaryGreen.withOpacity(0.04),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFEDF0EE),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.055),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              // ==================================================
              // ICONO
              // ==================================================

              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(17),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 29,
                  color: iconColor,
                ),
              ),

              const SizedBox(width: 16),

              // ==================================================
              // TEXTO
              // ==================================================

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDanger
                            ? const Color(0xFFB62D2D)
                            : ProfilePage.textDark,
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfilePage.textGrey,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // ==================================================
              // FLECHA
              // ==================================================

              Icon(
                Icons.chevron_right_rounded,
                color: isDanger
                    ? const Color(0xFFCB6B6B)
                    : const Color(0xFF7C8581),
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PIE DE PÁGINA
// ============================================================================

class _AniMapFooter extends StatelessWidget {
  const _AniMapFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: ProfilePage.lightGreen,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.pets_rounded,
            color: ProfilePage.darkGreen,
            size: 25,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'AniMap',
          style: TextStyle(
            color: ProfilePage.textGrey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// DIÁLOGO DE CONFIRMACIÓN
// ============================================================================

void _showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmText,
  required VoidCallback onConfirm,
  bool isDanger = false,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.38),
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titlePadding: const EdgeInsets.fromLTRB(
          24,
          24,
          24,
          8,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          24,
          6,
          24,
          18,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18,
        ),

        title: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: isDanger
                    ? const Color(0xFFFDECEC)
                    : ProfilePage.veryLightGreen,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isDanger
                    ? Icons.warning_amber_rounded
                    : Icons.logout_rounded,
                color: isDanger
                    ? Colors.red.shade600
                    : ProfilePage.darkGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: ProfilePage.textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),

        content: Text(
          message,
          style: const TextStyle(
            color: ProfilePage.textGrey,
            fontSize: 14,
            height: 1.45,
          ),
        ),

        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(
              foregroundColor: ProfilePage.textGrey,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: isDanger
                  ? Colors.red.shade600
                  : ProfilePage.darkGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              confirmText,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    },
  );
}