import 'package:animap/app.dart';
import 'package:animap/features/auth/data/auth_service.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/auth/presentation/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnverifiedAccountAuthService extends AuthService {
  String? loginEmail;
  String? resendEmail;
  String? verificationEmail;
  String? verificationCode;

  @override
  Future<String> getDeviceId() async => 'test-device';

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    loginEmail = email;
    throw AuthException('La cuenta aún no ha sido verificada');
  }

  @override
  Future<Map<String, dynamic>> resendVerificationCode({
    required String email,
  }) async {
    resendEmail = email;
    return {
      'message': 'Código reenviado',
      'data': {'sent': true},
    };
  }

  @override
  Future<Map<String, dynamic>> verifyAccount({
    required String email,
    required String code,
  }) async {
    verificationEmail = email;
    verificationCode = code;
    return {'message': 'Cuenta verificada exitosamente'};
  }
}

void main() {
  testWidgets('AniMap inicia en la pantalla de login', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      AniMapApp(
        sessionManager: SessionManager(storage: _MemorySessionStorage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Iniciar Sesión'), findsWidgets);
    expect(find.text('Registrarme'), findsOneWidget);
  });

  testWidgets(
    'cuenta no verificada puede reenviar, verificar y volver a Login',
    (tester) async {
      final authService = _UnverifiedAccountAuthService();
      const emailIngresado = 'Usuario.Pendiente@Example.com';
      const emailNormalizado = 'usuario.pendiente@example.com';

      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: LoginPage(authService: authService)),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo electrónico'),
        emailIngresado,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'ClaveTemporal123*',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar Sesión'));
      await tester.pumpAndSettle();

      expect(authService.loginEmail, emailNormalizado);
      expect(find.text('La cuenta aún no ha sido verificada'), findsOneWidget);
      expect(find.text('Verificar cuenta'), findsOneWidget);

      await tester.tap(find.text('Verificar cuenta'));
      await tester.pumpAndSettle();

      expect(find.text('Código de confirmación'), findsOneWidget);

      await tester.tap(find.text('Reenviar código'));
      await tester.pumpAndSettle();
      expect(authService.resendEmail, emailNormalizado);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verificar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(authService.verificationEmail, emailNormalizado);
      expect(authService.verificationCode, '123456');
      expect(find.byType(LoginPage), findsOneWidget);
    },
  );
}

class _MemorySessionStorage implements SessionStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
