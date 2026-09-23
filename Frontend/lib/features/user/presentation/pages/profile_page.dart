import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../../auth/data/session_manager.dart';
import '../../../auth/presentation/session_navigation.dart';
import '../../../pet/presentation/pages/my_pets_page.dart';
import '../../data/profile_service.dart';
import 'profile_options_pages.dart';
import '../widgets/profile_photo_preview.dart';

typedef ProfileLoader = Future<Map<String, dynamic>> Function();
typedef ProfilePhotoPicker = Future<XFile?> Function();
typedef ProfilePhotoUploader =
    Future<Map<String, dynamic>> Function(XFile image);

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
    this.profileLoader,
    this.photoPicker,
    this.photoUploader,
    this.personalProfileUpdater,
    this.sessionManager,
  });

  final VoidCallback? onMenu;
  final VoidCallback? onNotifications;
  final VoidCallback? onLogout;
  final VoidCallback? onDeleteAccount;

  final VoidCallback? onHome;
  final VoidCallback? onPets;
  final VoidCallback? onProfile;
  final ProfileLoader? profileLoader;
  final ProfilePhotoPicker? photoPicker;
  final ProfilePhotoUploader? photoUploader;
  final PersonalProfileUpdater? personalProfileUpdater;
  final SessionManager? sessionManager;

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF3F9B67);
  static const Color lightGreen = Color(0xFFD9F0E2);
  static const Color textDark = Color(0xFF263238);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<Map<String, dynamic>> _profileFuture;
  final ImagePicker _imagePicker = ImagePicker();
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() =>
      (widget.profileLoader ?? ProfileService.obtenerPerfil)();

  void _reloadProfile() {
    if (!mounted) return;

    setState(() {
      _profileFuture = _loadProfile();
    });
  }

  void _applyUpdatedProfile(Map<String, dynamic> profile) {
    if (!mounted) return;
    setState(() {
      _profileFuture = Future.value(Map<String, dynamic>.from(profile));
    });
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_uploadingPhoto) return;
    var chooseAnother = true;
    while (chooseAnother && mounted) {
      chooseAnother = false;
      final image = await (widget.photoPicker != null
          ? widget.photoPicker!()
          : _imagePicker.pickImage(source: ImageSource.gallery));
      if (image == null || !mounted) return;

      final validationMessage = await ProfileService.validarFotoPerfil(image);
      if (!mounted) return;
      if (validationMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(validationMessage)));
        return;
      }

      final result = await showDialog<ProfilePhotoPreviewResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProfilePhotoPreviewDialog(
          image: image,
          uploader: (selected) async {
            if (mounted) setState(() => _uploadingPhoto = true);
            try {
              return await (widget.photoUploader ??
                  ProfileService.actualizarFotoPerfil)(selected);
            } finally {
              if (mounted) setState(() => _uploadingPhoto = false);
            }
          },
        ),
      );
      if (!mounted || result == null) return;
      chooseAnother = result.action == ProfilePhotoPreviewAction.chooseAnother;
      if (result.action == ProfilePhotoPreviewAction.uploaded &&
          result.profile != null) {
        setState(() {
          _profileFuture = Future.value(result.profile!);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto de perfil actualizada')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildStatusScaffold(
            child: const CircularProgressIndicator(
              color: ProfilePage.darkGreen,
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          final message = snapshot.error is ProfileException
              ? (snapshot.error as ProfileException).message
              : 'No se pudo cargar el perfil';

          return _buildStatusScaffold(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _reloadProfile,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }

        return _buildProfile(context, snapshot.data!);
      },
    );
  }

  Widget _buildStatusScaffold({required Widget child}) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: AniMapSideMenu(sessionManager: widget.sessionManager),
      body: SafeArea(
        child: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
      bottomNavigationBar: const BottomMenuAnimap(currentIndex: 2),
    );
  }

  Widget _buildProfile(BuildContext context, Map<String, dynamic> profile) {
    final userName = profile['nombre']?.toString() ?? '';
    final email = profile['email']?.toString() ?? '';
    final profilePhotoUrl = ProfileService.absolutePhotoUrl(
      profile['foto_url'],
    );
    final ImageProvider? avatarImage =
        profilePhotoUrl != null && profilePhotoUrl.trim().isNotEmpty
        ? NetworkImage(profilePhotoUrl, headers: ProfileService.imageHeaders)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F4),
      drawer: AniMapSideMenu(sessionManager: widget.sessionManager),
      body: SafeArea(
        child: Column(
          children: [
            TopMenuAnimap(onNotificationTap: widget.onNotifications),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  _ProfileHeaderCard(
                    userName: userName,
                    email: email,
                    avatarImage: avatarImage,
                    uploadingPhoto: _uploadingPhoto,
                    onEditPhoto: _pickAndUploadPhoto,
                  ),
                  const SizedBox(height: 22),
                  const _SectionLabel('Tu cuenta'),
                  const SizedBox(height: 8),
                  _OptionsCard(
                    children: [
                      _ProfileOption(
                        icon: Icons.person,
                        text: 'Información Personal',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PersonalInfoPage(
                                profile: profile,
                                onUpdated: () {},
                                onProfileUpdated: _applyUpdatedProfile,
                                profileUpdater: widget.personalProfileUpdater,
                              ),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 58),
                      _ProfileOption(
                        icon: Icons.pets_rounded,
                        text: 'Mis Mascotas',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyPetsPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 58),
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
                      const Divider(height: 1, indent: 58),
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
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _SectionLabel('Seguridad'),
                  const SizedBox(height: 8),
                  _OptionsCard(
                    children: [
                      _ProfileOption(
                        icon: Icons.logout,
                        text: 'Cerrar sesión',
                        onTap: () async {
                          final loggedOut = await confirmLogoutAndNavigate(
                            context,
                            sessionManager: widget.sessionManager,
                          );
                          if (loggedOut) widget.onLogout?.call();
                        },
                      ),
                      const Divider(height: 1, indent: 58),
                      _ProfileOption(
                        icon: Icons.person_remove,
                        text: 'Eliminar cuenta',
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

                              ScaffoldMessenger.of(context).showSnackBar(
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
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'AniMap · cuidamos juntos de quienes más quieres',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF718078), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuAnimap(currentIndex: 2),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.userName,
    required this.email,
    required this.avatarImage,
    required this.uploadingPhoto,
    required this.onEditPhoto,
  });

  final String userName;
  final String email;
  final ImageProvider? avatarImage;
  final bool uploadingPhoto;
  final VoidCallback onEditPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4AAA70), Color(0xFF75C990)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260E5534),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'Editar foto de perfil',
            child: GestureDetector(
              onTap: uploadingPhoto ? null : onEditPhoto,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 62,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 57,
                      backgroundColor: const Color(0xFFD8E7DD),
                      backgroundImage: avatarImage,
                      onBackgroundImageError: avatarImage == null
                          ? null
                          : (_, _) {},
                      child: uploadingPhoto
                          ? const CircularProgressIndicator()
                          : avatarImage == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 66,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    right: -3,
                    bottom: 4,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7651),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            userName.isEmpty ? 'Usuario AniMap' : userName,
            key: const ValueKey('profile-header-name'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              email,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFEAF7EE), fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF66756D),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x22000000),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.icon,
    required this.text,
    this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? const Color(0xFFC83E45) : const Color(0xFF33483E);
    return ListTile(
      onTap: onTap,
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDanger ? const Color(0xFFFFECEC) : const Color(0xFFE7F4EB),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          icon,
          color: isDanger ? color : ProfilePage.darkGreen,
          size: 20,
        ),
      ),
      title: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: color.withValues(alpha: 0.65),
      ),
    );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              backgroundColor: isDanger
                  ? Colors.red.shade600
                  : ProfilePage.darkGreen,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
}
