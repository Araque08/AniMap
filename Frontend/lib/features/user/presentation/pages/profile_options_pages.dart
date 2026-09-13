import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/profile_service.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({
    super.key,
    required this.profile,
    required this.onUpdated,
  });

  final Map<String, dynamic> profile;
  final VoidCallback onUpdated;

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  bool _isSaving = false;
  File? _selectedImage;

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF2F8F5B);
  static const Color backgroundColor = Color(0xFFF5F8F6);
  static const Color textPrimary = Color(0xFF1C2B24);
  static const Color textSecondary = Color(0xFF718078);
  static const Color borderColor = Color(0xFFE3EAE6);

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.profile['nombre']?.toString() ?? '',
    );

    _phoneController = TextEditingController(
      text: widget.profile['telefono']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      await ProfileService.actualizarPerfil(
        nombre: _nameController.text.trim(),
        telefono: _phoneController.text.trim(),
      );

      /*
       * IMPORTANTE:
       * Aquí debe llamarse el método real de tu backend para subir la foto.
       *
       * Ejemplo, SOLO cuando ese método exista:
       *
       * if (_selectedImage != null) {
       *   await ProfileService.actualizarFotoPerfil(_selectedImage!);
       * }
       *
       * No se llama actualmente porque en el código compartido no aparece
       * ningún método/endpoint para cargar la imagen.
       */

      final refreshedProfile = await ProfileService.obtenerPerfil();

      if (!mounted) return;

      _nameController.text = refreshedProfile['nombre']?.toString() ?? '';
      _phoneController.text = refreshedProfile['telefono']?.toString() ?? '';

      widget.onUpdated();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text('Perfil actualizado correctamente'),
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
    } on ProfileException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } catch (_) {
      if (!mounted) return;
      _showError('No se pudo actualizar el perfil');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1200,
      );

      if (image == null || !mounted) return;

      setState(() {
        _selectedImage = File(image.path);
      });
    } catch (_) {
      if (!mounted) return;
      _showError('No se pudo seleccionar la imagen');
    }
  }

  void _showPhotoOptions() {
    if (_isSaving) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7DDD9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Cambiar foto de perfil',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Elige cómo deseas actualizar tu foto',
                  style: TextStyle(
                    fontSize: 13,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _PhotoOptionButton(
                        icon: Icons.photo_library_rounded,
                        title: 'Galería',
                        onTap: () {
                          Navigator.pop(context);
                          _pickImage(ImageSource.gallery);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PhotoOptionButton(
                        icon: Icons.photo_camera_rounded,
                        title: 'Cámara',
                        onTap: () {
                          Navigator.pop(context);
                          _pickImage(ImageSource.camera);
                        },
                      ),
                    ),
                  ],
                ),
                if (_selectedImage != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _selectedImage = null);
                      },
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Descartar nueva foto'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.profile['foto_url']?.toString();
    final hasNetworkPhoto =
        photoUrl != null && photoUrl.trim().isNotEmpty;

    ImageProvider? profileImage;

    if (_selectedImage != null) {
      profileImage = FileImage(_selectedImage!);
    } else if (hasNetworkPhoto) {
      profileImage = NetworkImage(photoUrl);
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        centerTitle: true,
        title: const Text(
          'Información personal',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.maybePop(context),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            children: [
              _buildProfileHeader(profileImage),
              const SizedBox(height: 20),

              _SectionCard(
                title: 'Datos personales',
                subtitle: 'Mantén actualizada tu información de contacto.',
                child: Column(
                  children: [
                    _ProfileField(
                      label: 'Nombre completo',
                      hintText: 'Ingresa tu nombre',
                      controller: _nameController,
                      icon: Icons.person_outline_rounded,
                      enabled: !_isSaving,
                      validator: (value) {
                        if (value == null || value.trim().length < 3) {
                          return 'El nombre es muy corto';
                        }

                        if (value.trim().length > 120) {
                          return 'El nombre es demasiado largo';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _ProfileField(
                      label: 'Correo electrónico',
                      initialValue:
                      widget.profile['email']?.toString() ?? '',
                      icon: Icons.mail_outline_rounded,
                      readOnly: true,
                      helperText: 'El correo no se puede modificar aquí',
                    ),
                    const SizedBox(height: 16),
                    _ProfileField(
                      label: 'Teléfono',
                      hintText: 'Ej. 300 123 4567',
                      controller: _phoneController,
                      icon: Icons.phone_outlined,
                      enabled: !_isSaving,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9+\-\s()]'),
                        ),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      validator: (value) {
                        final phone = value?.trim() ?? '';

                        if (phone.length < 10 ||
                            phone.length > 20 ||
                            !RegExp(r'^[0-9+\-\s()]+$').hasMatch(phone)) {
                          return 'Número de teléfono no válido';
                        }

                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              _infoBanner(),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: darkGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: darkGreen.withOpacity(.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isSaving
                        ? const Row(
                      key: ValueKey('saving'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Guardando cambios...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                        : const Row(
                      key: ValueKey('save'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 21),
                        SizedBox(width: 9),
                        Text(
                          'Guardar cambios',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ImageProvider? profileImage) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 124,
                height: 124,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryGreen,
                      darkGreen,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryGreen.withOpacity(.24),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFFE8F4EC),
                    backgroundImage: profileImage,
                    child: profileImage == null
                        ? const Icon(
                      Icons.person_rounded,
                      size: 58,
                      color: primaryGreen,
                    )
                        : null,
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: 2,
                child: Material(
                  color: darkGreen,
                  elevation: 4,
                  shadowColor: darkGreen.withOpacity(.3),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _showPhotoOptions,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _nameController.text.trim().isEmpty
                ? 'Tu perfil'
                : _nameController.text.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.profile['email']?.toString() ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: const Color(0xFFEAF7EF),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _showPhotoOptions,
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      size: 18,
                      color: darkGreen,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Cambiar foto',
                      style: TextStyle(
                        color: darkGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7EF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryGreen.withOpacity(.20),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: darkGreen,
            size: 23,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tu información personal ayuda a mantener tu cuenta actualizada y facilita el contacto dentro de AniMap.',
              style: TextStyle(
                height: 1.45,
                fontSize: 12.5,
                color: Color(0xFF4F6559),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  static const Color textPrimary = Color(0xFF1C2B24);
  static const Color textSecondary = Color(0xFF718078);
  static const Color borderColor = Color(0xFFE3EAE6);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.icon,
    this.controller,
    this.initialValue,
    this.hintText,
    this.helperText,
    this.readOnly = false,
    this.enabled = true,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final IconData icon;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hintText;
  final String? helperText;
  final bool readOnly;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF2F8F5B);
  static const Color borderColor = Color(0xFFE3EAE6);
  static const Color textPrimary = Color(0xFF1C2B24);
  static const Color textSecondary = Color(0xFF718078);

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      readOnly: readOnly,
      enabled: enabled,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: helperText,
        helperMaxLines: 2,
        labelStyle: const TextStyle(
          color: textSecondary,
          fontSize: 13,
        ),
        floatingLabelStyle: const TextStyle(
          color: darkGreen,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFFAAB4AE),
          fontWeight: FontWeight.w400,
        ),
        helperStyle: const TextStyle(
          color: textSecondary,
          fontSize: 11,
        ),
        prefixIcon: Icon(
          icon,
          color: readOnly ? textSecondary : darkGreen,
          size: 21,
        ),
        suffixIcon: readOnly
            ? const Icon(
          Icons.lock_outline_rounded,
          color: Color(0xFFAAB4AE),
          size: 18,
        )
            : null,
        filled: true,
        fillColor: readOnly
            ? const Color(0xFFF2F4F3)
            : const Color(0xFFF8FAF9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: primaryGreen,
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.red.shade400,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.red.shade500,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _PhotoOptionButton extends StatelessWidget {
  const _PhotoOptionButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  static const Color darkGreen = Color(0xFF2F8F5B);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F8F5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 18,
          ),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFFE3F4E9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: darkGreen,
                  size: 23,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C2B24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
