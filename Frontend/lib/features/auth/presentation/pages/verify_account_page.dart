import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/auth_service.dart';
import 'login_page.dart';

/*
  Aquí hicimos la pantalla de verificación de cuenta.
  Esta pantalla recibe el correo del usuario y permite escribir el código
  de 6 dígitos que genera el backend.
*/
class VerifyAccountPage extends StatefulWidget {
  final String email;
  final AuthService? authService;

  const VerifyAccountPage({super.key, required this.email, this.authService});

  @override
  State<VerifyAccountPage> createState() => _VerifyAccountPageState();
}

class _VerifyAccountPageState extends State<VerifyAccountPage> {
  late final AuthService _authService;
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  static const Color backgroundColor = Color(0xFFEAF5E6);
  static const Color primaryGreen = Color(0xFF6EC656);
  static const Color darkText = Color(0xFF415466);

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /*
    Aquí hicimos la función que verifica la cuenta.
    Tomamos el código escrito por el usuario y lo enviamos al backend.
  */
  Future<void> _verifyAccount() async {
    final code = _codeController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _errorMessage = 'El código debe tener 6 dígitos';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _authService.verifyAccount(email: widget.email, code: code);

      if (!mounted) return;

      setState(() {
        _successMessage = 'Cuenta verificada exitosamente';
        _errorMessage = null;
      });

      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginPage(authService: _authService)),
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.message;
        _successMessage = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'No se pudo verificar la cuenta';
        _successMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /*
    Aquí hicimos la función para reenviar el código.
    Si el usuario no recibió el código o el código venció, puede pedir uno nuevo.
  */
  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await _authService.resendVerificationCode(
        email: widget.email,
      );

      if (!mounted) return;

      final sent = response['data']?['sent'] == true;
      final message =
          response['message']?.toString() ?? 'No se pudo completar el reenvío';

      setState(() {
        _successMessage = sent ? message : null;
        _errorMessage = sent ? null : message;
      });
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.message;
        _successMessage = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'No se pudo reenviar el código';
        _successMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /*
    Aquí construimos la interfaz visual siguiendo el diseño de confirmación:
    logo, título, explicación, campo del código, opción de reenviar y botón verificar.
  */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: -40,
              right: -40,
              bottom: -10,
              child: Container(
                height: 105,
                decoration: BoxDecoration(
                  color: primaryGreen.withOpacity(0.30),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.elliptical(500, 120),
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 45),
                    Image.asset(
                      'assets/images/Logo_Principal_AniMap.png',
                      height: 155,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Código de confirmación',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: darkText,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 42),
                    Text(
                      'Tu cuenta fue creada correctamente, pero aún no ha sido verificada.\n'
                      'Te enviamos un código de verificación a tu correo electrónico.\n'
                      'Ingresa el código para activar tu cuenta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: darkText.withOpacity(0.65),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 70),
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      textAlign: TextAlign.left,
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Ingresa el código',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide(
                            color: Colors.grey.withOpacity(0.25),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide(
                            color: Colors.grey.withOpacity(0.25),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(
                            color: primaryGreen,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '¿No recibiste el código?',
                          style: TextStyle(
                            color: darkText.withOpacity(0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextButton(
                          onPressed: _isLoading ? null : _resendCode,
                          child: const Text(
                            'Reenviar código',
                            style: TextStyle(
                              color: Color(0xFF4D9E5D),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_errorMessage != null)
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (_successMessage != null)
                      Text(
                        _successMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF20B43F),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verifyAccount,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: primaryGreen.withOpacity(
                            0.55,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.3,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Verificar',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 40),
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
