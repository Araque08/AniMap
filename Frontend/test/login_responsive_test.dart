import 'package:animap/features/auth/presentation/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final keyboardHeight in [0.0, 260.0]) {
    testWidgets(
      'Login a 320px con teclado $keyboardHeight permite validar y navegar',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const MaterialApp(home: LoginPage()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final submit = find.widgetWithText(ElevatedButton, 'Iniciar Sesión');
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('Ingresa tu correo'), findsOneWidget);
        expect(find.text('Ingresa tu contraseña'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          tester.getTopLeft(find.text('¿Olvidó su contraseña?')).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(find.text('Ingresa tu contraseña')).dy,
          ),
          reason: 'El enlace no debe tapar el error de contraseña',
        );

        await tester.ensureVisible(find.text('Registrarme'));
        await tester.pumpAndSettle();
        expect(find.text('Registrarme').hitTestable(), findsOneWidget);
      },
    );
  }
}
