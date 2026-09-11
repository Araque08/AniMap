import 'package:flutter/material.dart';

import '../../data/auth_service.dart';

class ResetPasswordPage extends StatefulWidget {
  final String email;

  const ResetPasswordPage({
    super.key,
    required this.email,
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
  TextEditingController();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.resetPassword(
        email: widget.email.trim().toLowerCase(),
        code: _codeController.text.trim(),
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Contraseña actualizada',
            ),
            content: const Text(
              'Tu contraseña fue restablecida correctamente. '
                  'Ya puedes iniciar sesión con tu nueva contraseña.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text(
                  'Aceptar',
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      /*
        Regresamos hasta la pantalla de inicio de sesión.
      */
      Navigator.of(context).popUntil(
            (route) => route.isFirst,
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
        'Ocurrió un error inesperado al restablecer la contraseña.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresa una contraseña';
    }

    if (value.length < 8) {
      return 'Debe tener mínimo 8 caracteres';
    }

    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Debe incluir una mayúscula';
    }

    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Debe incluir una minúscula';
    }

    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Debe incluir un número';
    }

    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(value)) {
      return 'Debe incluir un carácter especial';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFDDE6D8);
    const Color primaryGreen = Color(0xFF73C15A);
    const Color darkText = Color(0xFF415466);
    const Color accentGreen = Color(0xFF2E8B57);
    const Color hintText = Color(0xFFB8B8B8);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomWaves(),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 35,
                vertical: 15,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(
                          Icons.arrow_back,
                          color: darkText,
                        ),
                      ),
                    ),

                    Image.asset(
                      'assets/images/Logo_Principal_AniMap.png',
                      height: 150,
                      fit: BoxFit.contain,
                    ),

                    const SizedBox(height: 15),

                    const Text(
                      'Nueva contraseña',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        color: darkText,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Ingresa el código que enviamos a\n${widget.email}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7E8A82),
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 30),

                    TextFormField(
                      controller: _codeController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: _inputDecoration(
                        hint: 'Código de 6 dígitos',
                        prefixIcon: Icons.verified_user_outlined,
                        hintTextColor: hintText,
                        iconColor: accentGreen,
                      ).copyWith(
                        counterText: '',
                      ),
                      validator: (value) {
                        final code = value?.trim() ?? '';

                        if (code.isEmpty) {
                          return 'Ingresa el código';
                        }

                        if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                          return 'El código debe tener 6 dígitos';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNewPassword,
                      enabled: !_isLoading,
                      decoration: _inputDecoration(
                        hint: 'Nueva contraseña',
                        prefixIcon: Icons.lock_outline,
                        hintTextColor: hintText,
                        iconColor: accentGreen,
                        suffixIcon: IconButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                            setState(() {
                              _obscureNewPassword =
                              !_obscureNewPassword;
                            });
                          },
                          icon: Icon(
                            _obscureNewPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: accentGreen,
                          ),
                        ),
                      ),
                      validator: _validatePassword,
                    ),

                    const SizedBox(height: 18),

                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      enabled: !_isLoading,
                      decoration: _inputDecoration(
                        hint: 'Confirmar contraseña',
                        prefixIcon: Icons.lock_outline,
                        hintTextColor: hintText,
                        iconColor: accentGreen,
                        suffixIcon: IconButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                            setState(() {
                              _obscureConfirmPassword =
                              !_obscureConfirmPassword;
                            });
                          },
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: accentGreen,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final passwordError =
                        _validatePassword(value);

                        if (passwordError != null) {
                          return passwordError;
                        }

                        if (value != _newPasswordController.text) {
                          return 'Las contraseñas no coinciden';
                        }

                        return null;
                      },
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed:
                        _isLoading ? null : _resetPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'Cambiar contraseña',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 150),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    required Color hintTextColor,
    required Color iconColor,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF6F6F4),
      hintText: hint,
      hintStyle: TextStyle(
        color: hintTextColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(
        prefixIcon,
        color: iconColor,
      ),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 18,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: Color(0xFFD7DDD3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: Color(0xFF7FB191),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: Colors.redAccent,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: Colors.redAccent,
          width: 1.5,
        ),
      ),
    );
  }
}


/*
  Olas inferiores para mantener el diseño visual de AniMap
  utilizado en la pantalla de inicio de sesión.
*/
class _BottomWaves extends StatelessWidget {
  const _BottomWaves();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _BottomWavesPainter(),
      ),
    );
  }
}


class _BottomWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint darkWave = Paint()
      ..color = const Color(0xFFCFE7D8)
      ..style = PaintingStyle.fill;

    final Paint middleWave = Paint()
      ..color = const Color(0xFFB4D6CA)
      ..style = PaintingStyle.fill;

    final Paint lightWave = Paint()
      ..color = const Color(0xFF7CC484)
      ..style = PaintingStyle.fill;

    final Path darkPath = Path()
      ..moveTo(0, size.height * 0.50)
      ..quadraticBezierTo(
        size.width * 0.20,
        size.height * 0.18,
        size.width * 0.42,
        size.height * 0.22,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.35,
        size.width,
        size.height * 0.28,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final Path middlePath = Path()
      ..moveTo(0, size.height * 0.38)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.20,
        size.width * 0.46,
        size.height * 0.45,
      )
      ..quadraticBezierTo(
        size.width * 0.74,
        size.height * 0.74,
        size.width,
        size.height * 0.60,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final Path lightPath = Path()
      ..moveTo(0, size.height * 0.49)
      ..quadraticBezierTo(
        size.width * 0.24,
        size.height * 0.34,
        size.width * 0.50,
        size.height * 0.59,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.85,
        size.width,
        size.height * 0.73,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(darkPath, darkWave);
    canvas.drawPath(middlePath, middleWave);
    canvas.drawPath(lightPath, lightWave);
  }

  @override
  bool shouldRepaint(
      covariant CustomPainter oldDelegate,
      ) {
    return false;
  }
}