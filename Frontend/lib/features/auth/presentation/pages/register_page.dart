import 'package:flutter/material.dart';
import 'login_page.dart';
import '../../data/auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
  TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedPolicies = false;

  static const Color backgroundColor = Color(0xFFDDE6D8);
  static const Color primaryGreen = Color(0xFF73C15A);
  static const Color darkText = Color(0xFF415466);
  static const Color hintText = Color(0xFFBFC5BF);
  static const Color accentGreen = Color(0xFF3F9E57);
  static const Color inputBackground = Color(0xFFF7F7F5);
  static const Color inputBorder = Color(0xFFC8D1C3);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitRegister() async {
    final isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid) return;

    if (!_acceptedPolicies) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes aceptar los términos y condiciones y la política de privacidad.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _authService.register(
        nombre: _nameController.text.trim(),
        email: _emailController.text.trim(),
        telefono: _phoneController.text.trim(),
        password: _passwordController.text,
        aceptaTyC: _acceptedPolicies,
      );

      final user = response['data'];
      final nombre = user?['nombre']?.toString() ?? 'usuario';

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Registro exitoso para $nombre. Tu cuenta quedó pendiente de verificación.',
          ),
        ),
      );

      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        _goToLogin();
      });
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ocurrió un error inesperado al registrar el usuario'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomWaves(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 5),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 12),

                    Image.asset(
                      'assets/images/Logo_Principal_AniMap.png',
                      height: 180,
                      fit: BoxFit.contain,
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Crear Nueva Cuenta',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        color: darkText,
                      ),
                    ),


                    /*RichText(
                      textAlign: TextAlign.center,
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF93A195),
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(text: 'Registrate para comenzar a usar '),
                          TextSpan(
                            text: 'AniMap',
                            style: TextStyle(
                              color: accentGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),*/


                    SizedBox(
                      width: 330,
                      height: 65,
                      child:TextFormField(
                          controller: _nameController,
                          decoration: _inputDecoration(
                            hint: 'Tu nombre completo',
                            prefixIcon: Icons.person,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa tu nombre';
                            }
                            if (value.trim().length < 3) {
                              return 'Nombre muy corto';
                            }
                            return null;
                          },
                      ),
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: 330,
                      height: 65,
                      child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _inputDecoration(
                            hint: 'Correo electrónico',
                            prefixIcon: Icons.email,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa tu correo';
                            }

                            final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                            if (!emailRegex.hasMatch(value.trim())) {
                              return 'Correo no válido';
                            }

                            return null;
                          },

                      ),
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: 330,
                      height: 65,
                      child:TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: _inputDecoration(
                            hint: 'Número de teléfono',
                            prefixIcon: Icons.phone,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa tu teléfono';
                            }

                            final phone = value.replaceAll(RegExp(r'\s+'), '');
                            if (phone.length < 10) {
                              return 'Número no válido';
                            }

                            return null;
                          },
                      ),
                    ),


                    const SizedBox(height: 8),

                    SizedBox(
                      width: 330,
                      height: 65,
                      child:TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: _inputDecoration(
                            hint: 'Crea una contraseña',
                            prefixIcon: Icons.lock,
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: accentGreen,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Ingresa una contraseña';
                            }
                            if (value.length < 6) {
                              return 'Mínimo 6 caracteres';
                            }
                            return null;
                          },
                      ),
                    ),
                    const SizedBox(height: 8),

                    SizedBox(
                      width: 330,
                      height: 65,
                      child:TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: _inputDecoration(
                            hint: 'Confirmar contraseña',
                            prefixIcon: Icons.lock,
                            suffixIcon: IconButton(
                              onPressed: () {
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
                            if (value == null || value.isEmpty) {
                              return 'Confirma tu contraseña';
                            }
                            if (value != _passwordController.text) {
                              return 'Las contraseñas no coinciden';
                            }
                            return null;
                          },
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -2),
                          child: Checkbox(
                            value: _acceptedPolicies,
                            onChanged: (value) {
                              setState(() {
                                _acceptedPolicies = value ?? false;
                              });
                            },
                            activeColor: accentGreen,
                            side: const BorderSide(color: inputBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Expanded(
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                color: Color(0xFF7F8D81),
                                fontSize: 14,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                TextSpan(text: 'He leído y acepto los '),
                                TextSpan(
                                  text: 'Términos y Condiciones',
                                  style: TextStyle(
                                    color: accentGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: ' y '),
                                TextSpan(
                                  text: 'Política de Privacidad.',
                                  style: TextStyle(
                                    color: accentGreen,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitRegister,
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
                            strokeWidth: 2.6,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'Registrarme',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '¿Ya tienes una cuenta? ',
                          style: TextStyle(
                            color: Color(0xFF8E9890),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        GestureDetector(
                          onTap: _goToLogin,
                          child: const Text(
                            'Iniciar Sesión',
                            style: TextStyle(
                              color: accentGreen,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),
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
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: inputBackground,
      hintText: hint,
      hintStyle: const TextStyle(
        color: hintText,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(prefixIcon, color: accentGreen),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 17),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accentGreen, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }
}

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
      ..color = const Color(0xFFcfe7d8)
      ..style = PaintingStyle.fill;

    final Paint middleWave = Paint()
      ..color = const Color(0xFFb4d6ca)
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
      ..moveTo(1, size.height * 0.38)
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
      ..moveTo(2, size.height * 0.49)
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}