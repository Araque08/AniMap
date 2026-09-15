import 'package:flutter/material.dart';
import 'register_page.dart';
import '../../data/auth_service.dart';

import 'forgot_password_page.dart';
import 'verify_account_page.dart';
// Panel de inicio de AniMap usuarios
import '../../../map/presentation/pages/map_page.dart';

// Panel de administración de AniMap
import '../../../admin/presentation/pages/home admin/admin_home_page.dart';
import '../../../admin/presentation/pages/faq/admin_faq_page.dart';

class LoginPage extends StatefulWidget {
  final AuthService? authService;

  const LoginPage({super.key, this.authService});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final AuthService _authService;
  /* Estados en los que puede estar el logIn */
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _hasLoginError = false;
  String? _unverifiedEmail;
  String? _loginErrorMessage;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /* Envio del formulario logIn*/
  Future<void> _submitLogin() async {
    final isValid = _formKey.currentState?.validate() ?? false;

    /* valida si es correcto el ingreso */
    if (!isValid) return;

    final email = _emailController.text.trim().toLowerCase();

    setState(() {
      _isLoading = true;
      _hasLoginError = false;
      _unverifiedEmail = null;
      _loginErrorMessage = null;
    });

    try {
      /*
      Enviamos las credenciales al backend.
    */
      final response = await _authService.login(
        email: email,
        password: _passwordController.text,
        deviceId: 'android-emulador',
      );

      /*
      Obtenemos la información devuelta
      por el backend.
    */
      final data = response['data'];
      final user = data?['user'];

      final nombre =
          user?['nombre']?.toString() ?? 'usuario';

      /*
      Obtenemos el rol real almacenado
      en PostgreSQL.

      Ejemplos:
      ADMINISTRADOR
      USUARIO
    */
      final rol = user?['rol']
          ?.toString()
          .trim()
          .toUpperCase();

      if (!mounted) return;

      /*
      Dependiendo del rol dirigimos al usuario
      a la sección correspondiente de AniMap.
    */
      if (rol == 'ADMINISTRADOR') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
            const AdminHomePage(),
          ),
        );

        return;
      }

      if (rol == 'USUARIO') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                MapPage(userName: nombre),
          ),
        );

        return;
      }

      /*
      Si por alguna razón el backend devuelve
      un usuario sin un rol reconocido,
      evitamos darle acceso a alguna sección.
    */
      setState(() {
        _hasLoginError = true;
        _loginErrorMessage =
        'La cuenta no tiene un rol válido asignado';
      });
    } on AuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _hasLoginError = true;

        _unverifiedEmail =
        e.message ==
            'La cuenta aún no ha sido verificada'
            ? email
            : null;

        _loginErrorMessage =
        e.message == 'Credenciales inválidas'
            ? 'Correo o contraseña incorrectos'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _hasLoginError = true;
        _unverifiedEmail = null;
        _loginErrorMessage =
        'Error inesperado al iniciar sesión';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /* este guia a la pagina de Registrarse  */
  void _goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterPage()),
    );
  }

  /* Este guiara a la pagina para la recuperacion de la cuenta */
  void _forgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
    );
  }

  /* Permite continuar la verificación usando el correo escrito en Login. */
  void _verifyAccount() {
    final email = _unverifiedEmail;
    if (email == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            VerifyAccountPage(email: email, authService: _authService),
      ),
    );
  }

  /* Este guiara al proceso de iniciar sesion con google */
  void _loginWithGoogle() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aquí irá el inicio de sesión con Google.')),
    );
  }

  /* Desde esta parte se diseña la interfaz de la pagina*/
  @override
  Widget build(BuildContext context) {
    /* colores insignia para el diseño de la interfaz */
    const Color backgroundColor = Color(0xFFDDE6D8);
    const Color primaryGreen = Color(0xFF73C15A);
    const Color darkText = Color(0xFF415466);
    const Color hintText = Color(0xFFB8B8B8);
    const Color accentGreen = Color(0xFF2E8B57);

    return Scaffold(
      /* Fondo de la pagina*/
      backgroundColor: backgroundColor,
      /* Evita redimensionar la pagina cada vez que se abre el teclado*/
      resizeToAvoidBottomInset: false,

      body: Stack(
        children: [
          const Positioned(left: 0, right: 0, bottom: 0, child: _BottomWaves()),
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
                      'Iniciar Sesión',
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
                          TextSpan(
                            text: 'AniMap',
                            style: TextStyle(
                              color: accentGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: 190,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _loginWithGoogle,
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
                    const Row(
                      children: const [
                        Expanded(
                          child: Divider(color: Colors.black54, thickness: 1),
                        ),
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
                        Expanded(
                          child: Divider(color: Colors.black54, thickness: 1),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),
                    /* Creacion del campo de texto para el correo electronico*/
                    SizedBox(
                      width: 330,
                      height: 75,
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_isLoading,
                        decoration: _inputDecoration(
                          hint: 'Correo electrónico',
                          /* icono para el input email */
                          prefixIcon: Icons.email,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasLoginError,
                        ),
                        /* valida el valor que le llega al input al ser preseionado*/
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa tu correo';
                          }

                          final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                          /* Valida que ell correo sea valido*/
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Correo no válido';
                          }

                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 18),
                    /* Creacion del campo de contraseña */
                    SizedBox(
                      width: 330,
                      height: 75,
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        enabled: !_isLoading,
                        decoration: _inputDecoration(
                          hint: 'Contraseña',
                          /* icono para el input contraseña */
                          prefixIcon: Icons.lock,
                          hintTextColor: hintText,
                          iconColor: accentGreen,
                          hasError: _hasLoginError,
                          suffixIcon: IconButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                            /* Iconos de ver y ocultar contraseña*/
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: _hasLoginError
                                  ? Colors.redAccent
                                  : accentGreen,
                            ),
                          ),
                        ),
                        /* valida el campo contraseña */
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            /* si esta vacio el campo le aparece el texto */
                            return 'Ingresa tu contraseña';
                          }
                          return null;
                        },
                      ),
                    ),
                    /* se crea el enlace si el usuario olvido la cotraseña */
                    Transform.translate(
                      offset: const Offset(0, -15),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _isLoading ? null : _forgotPassword,
                          child: const Text(
                            '¿Olvidó su contraseña?',
                            style: TextStyle(
                              color: Color(0xFF418452),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (_hasLoginError && _loginErrorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _loginErrorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _hasLoginError = false;
                            _unverifiedEmail = null;
                            _loginErrorMessage = null;
                          });
                        },
                        child: const Text(
                          'Intenta nuevamente',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_unverifiedEmail != null)
                        TextButton(
                          onPressed: _isLoading ? null : _verifyAccount,
                          child: const Text(
                            'Verificar cuenta',
                            style: TextStyle(
                              color: Color(0xFF418452),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],

                    SizedBox(height: _hasLoginError ? 12 : 45),

                    SizedBox(
                      width: 330,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: primaryGreen.withOpacity(
                            0.55,
                          ),
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
                                'Iniciar Sesión',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 7),
                    /* Este crea la confirmacion de si el usuario tiene una cuenta  */
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '¿No tienes cuenta? ',
                          style: TextStyle(
                            color: Color(0xFF8B9790),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        /* si el usuario no tiene cuanta puede seguir a la pagina Registrarse*/
                        GestureDetector(
                          onTap: _isLoading ? null : _goToRegister,
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

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* Decoracion para los diferentes inputs que hay en la interfaz*/
  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    required Color hintTextColor,
    required Color iconColor,
    bool hasError = false,
    Widget? suffixIcon,
  }) {
    final Color borderColor = hasError
        ? Colors.redAccent
        : const Color(0xFFD7DDD3);

    final Color focusedBorderColor = hasError
        ? Colors.redAccent
        : const Color(0xFF7FB191);

    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF6F6F4),
      hintText: hint,
      hintStyle: TextStyle(color: hintTextColor, fontWeight: FontWeight.w700),
      prefixIcon: Icon(
        prefixIcon,
        color: hasError ? Colors.redAccent : iconColor,
      ),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: focusedBorderColor, width: 1.5),
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

/* En esta parte se crean las diferentes olas que se encuentran en footer de la hoja */
class _BottomWaves extends StatelessWidget {
  const _BottomWaves();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(painter: _BottomWavesPainter()),
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

    /* ola #1 */

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

    /* ola #2 */

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

    /* ola #3 */

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
