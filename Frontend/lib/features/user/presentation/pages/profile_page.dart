import 'package:flutter/material.dart';
import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../../map/presentation/pages/map_page.dart';
import 'profile_options_pages.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    this.userName = 'Felipe Meza Rodríguez',
    this.profilePhotoUrl,
    this.onMenu,
    this.onNotifications,
    this.onLogout,
    this.onDeleteAccount,
    this.onHome,
    this.onPets,
    this.onProfile,
  });

  final String userName;
  final String? profilePhotoUrl;

  final VoidCallback? onMenu;
  final VoidCallback? onNotifications;
  final VoidCallback? onLogout;
  final VoidCallback? onDeleteAccount;

  final VoidCallback? onHome;
  final VoidCallback? onPets;
  final VoidCallback? onProfile;

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);
  static const Color lightGreen = Color(0xFFD9F0E2);
  static const Color textDark = Color(0xFF263238);

  @override
  Widget build(BuildContext context) {
    final ImageProvider? avatarImage =
    profilePhotoUrl != null && profilePhotoUrl!.trim().isNotEmpty
        ? NetworkImage(profilePhotoUrl!)
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const AniMapSideMenu(),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              userName: userName,
              avatarImage: avatarImage,
              onMenu: onMenu,
              onNotifications: onNotifications,
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    _ProfileOption(
                      icon: Icons.person,
                      text: 'Información Personal',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PersonalInfoPage(),
                          ),
                        );
                      },
                    ),
                    _ProfileOption(
                      icon: Icons.lock,
                      text: 'Sesiones activas',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ActiveSessionsPage(),
                          ),
                        );
                      },
                    ),
                    _ProfileOption(
                      icon: Icons.settings_applications,
                      text: 'Preferencias de notificación',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                            const NotificationPreferencesPage(),
                          ),
                        );
                      },
                    ),
                    _ProfileOption(
                      icon: Icons.logout,
                      text: 'Cerrar sesión',
                      onTap: () {
                        _showConfirmDialog(
                          context: context,
                          title: 'Cerrar sesión',
                          message:
                          '¿Estás seguro de que deseas cerrar tu sesión?',
                          confirmText: 'Cerrar sesión',
                          onConfirm: () {
                            Navigator.pop(context);

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                Text('Sesión cerrada correctamente'),
                              ),
                            );

                            if (onLogout != null) {
                              onLogout!();
                            }
                          },
                        );
                      },
                    ),
                    _ProfileOption(
                      icon: Icons.person_remove,
                      text: 'Eliminar cuenta',
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

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Solicitud de eliminación de cuenta realizada',
                                ),
                              ),
                            );

                            if (onDeleteAccount != null) {
                              onDeleteAccount!();
                            }
                          },
                        );
                      },
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 80,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _BottomWavePainter(),
                      ),
                    ),
                  ],
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

class _Header extends StatelessWidget {
  const _Header({
    required this.userName,
    required this.avatarImage,
    this.onMenu,
    this.onNotifications,
  });

  final String userName;
  final ImageProvider? avatarImage;
  final VoidCallback? onMenu;
  final VoidCallback? onNotifications;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 245,
      width: double.infinity,
      child: Stack(
        children: [
          ClipPath(
            clipper: _HeaderClipper(),
            child: Container(
              height: 190,
              color: ProfilePage.primaryGreen,
            ),
          ),
          const TopMenuAnimap(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFFD7D7D7),
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? const Icon(
                      Icons.person,
                      size: 58,
                      color: Colors.white,
                    )
                        : null,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  userName,
                  style: const TextStyle(
                    color: ProfilePage.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.icon,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 245,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Color(0xFF777777),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 35,
                child: Icon(
                  icon,
                  color: Colors.black,
                  size: 21,
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.lineTo(0, size.height * 0.82);

    path.quadraticBezierTo(
      size.width * 0.35,
      size.height * 0.92,
      size.width * 0.65,
      size.height * 0.78,
    );

    path.quadraticBezierTo(
      size.width * 0.84,
      size.height * 0.69,
      size.width,
      size.height * 0.65,
    );

    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
  }
}

class _BottomWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLight = Paint()
      ..color = ProfilePage.lightGreen
      ..style = PaintingStyle.fill;

    final paintGreen = Paint()
      ..color = ProfilePage.primaryGreen.withOpacity(0.45)
      ..style = PaintingStyle.fill;

    final pathLight = Path()
      ..moveTo(0, size.height * 0.45)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.25,
        size.width * 0.55,
        size.height * 0.42,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.57,
        size.width,
        size.height * 0.35,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final pathGreen = Path()
      ..moveTo(0, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.45,
        size.width * 0.7,
        size.height * 0.66,
      )
      ..quadraticBezierTo(
        size.width * 0.87,
        size.height * 0.76,
        size.width,
        size.height * 0.52,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(pathLight, paintLight);
    canvas.drawPath(pathGreen, paintGreen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

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
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor:
              isDanger ? Colors.red.shade600 : ProfilePage.darkGreen,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
}