import 'package:flutter/material.dart';
import 'register_page.dart';
import '../../data/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    final isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        deviceId: 'android-emulador',
      );

      final user = response['data']?['user'];
      final nombre = user?['nombre']?.toString() ?? 'usuario';

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Inicio de sesión exitoso. Bienvenido, $nombre'),
        ),
      );

      // Aquí después navegaremos al home o perfil.
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
          content: Text('Ocurrió un error inesperado al iniciar sesión'),
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

  void _goToRegister() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RegisterPage(),
        ),
      );
  }

  void _forgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Aquí irá la recuperación de contraseña.'),
      ),
    );
  }

  void _loginWithGoogle() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Aquí irá el inicio de sesión con Google.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFDDE6D8);
    const Color primaryGreen = Color(0xFF73C15A);
    const Color darkText = Color(0xFF415466);
    const Color hintText = Color(0xFFB8B8B8);
    const Color accentGreen = Color(0xFF2E8B57);

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
                    const SizedBox(height: 20),

                    Image.asset(
                      'assets/images/Logo_Principal_AniMap.png',
                      height: 180,
                      fit: BoxFit.contain,
                    ),

                    const SizedBox(height: 20),
                    const Text(
                      'Iniciar Sesion',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        color: darkText,
                      ),
                    ),

                    const SizedBox(height: 5),

                    RichText(
                      textAlign: TextAlign.center,
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF97A39B),
                          fontWeight: FontWeight.w500,
                        ),
                        children: [
                          TextSpan(text: 'La vida es más feliz con mascotas. '),
                          /*TextSpan(
                            text: 'AniMap',
                            style: TextStyle(
                              color: accentGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),*/
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: 190,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _loginWithGoogle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.black,
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                            side: const BorderSide(color: Colors.black54),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/images/icono_google.png',
                              width: 22,
                              height: 22,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Google',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    Row(
                      children: const [
                        Expanded(child: Divider(color: Colors.black54, thickness: 1)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Or',
                            style: TextStyle(
                              color: Color(0xFF7E847F),
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.black54, thickness: 1)),
                      ],
                    ),

                    const SizedBox(height: 30),

                    SizedBox(
                      width: 330,
                      height: 75,
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDecoration(
                          hint: 'Correo electrónico',
                          prefixIcon: Icons.email,
                          hintTextColor: hintText,
                          iconColor: accentGreen,

                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa tu correo';
                          }

                          final emailRegex = RegExp(
                            r'^[^@]+@[^@]+\.[^@]+$',
                          );

                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Correo no válido';
                          }

                          return null;
                        },
                      ),
                    ),



                    const SizedBox(height: 18),

                    SizedBox(
                      width: 330,
                      height: 75,
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: _inputDecoration(
                          hint: 'Contraseña',
                          prefixIcon: Icons.lock,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
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
                            return 'Ingresa tu contraseña';
                          }

                          if (value.length < 6) {
                            return 'Mínimo 6 caracteres';
                          }

                          return null;
                        },
                      ),
                    ),




                    Transform.translate(
                      offset: const Offset(0, -15),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _forgotPassword,
                          child: const Text(
                            'Olvido su Contraseña?',
                            style: TextStyle(
                              color: Color(0xFF418452),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 65),

                    SizedBox(
                      width: 330,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _submitLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'Iniciar Sesion',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 7),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'No tengo Cuenta? ',
                          style: TextStyle(
                            color: Color(0xFF8B9790),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        GestureDetector(
                          onTap: _goToRegister,
                          child: const Text(
                            'Registrarme',
                            style: TextStyle(
                              color: accentGreen,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    //const SizedBox(height: 90),
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
      prefixIcon: Icon(prefixIcon, color: iconColor),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD7DDD3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF7FB191), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
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