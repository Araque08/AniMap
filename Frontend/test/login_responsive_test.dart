import 'package:animap/features/auth/presentation/pages/login_page.dart';
import 'package:animap/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:animap/features/auth/presentation/pages/register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder loginField(String hint) => find.widgetWithText(TextFormField, hint);

Finder get waves => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter.runtimeType.toString() == '_BottomWavesPainter',
);

void expectAboveKeyboard(
  WidgetTester tester,
  Finder field,
  Size screen,
  double keyboard,
) {
  final bounds = tester.getRect(field);
  expect(bounds.top, greaterThanOrEqualTo(24));
  expect(
    bounds.bottom,
    lessThanOrEqualTo(screen.height - keyboard),
    reason:
        'Todo el campo, no solo el cursor, debe quedar por encima del teclado',
  );
  expect(field.hitTestable(), findsOneWidget);
}

class LoginRouteObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
    super.didPush(route, previousRoute);
  }
}

void main() {
  for (final screen in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(400, 824),
  ]) {
    for (final keyboard in [0.0, 300.0]) {
      testWidgets(
        'footer ocupa el ancho y alto disponible en $screen con teclado $keyboard',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = screen;
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.padding = FakeViewPadding(
            top: 24,
            bottom: keyboard == 0 ? 24 : 0,
          );
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(const MaterialApp(home: LoginPage()));
          await tester.pumpAndSettle();
          final footer = tester.getRect(waves);
          expect(footer.bottom, closeTo(screen.height - keyboard, 0.01));
          expect(footer.left, 0);
          expect(footer.right, screen.width);
          await tester.ensureVisible(loginField('Contraseña'));
          await tester.pumpAndSettle();
          expectAboveKeyboard(
            tester,
            loginField('Contraseña'),
            screen,
            keyboard,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('Google, recuperación y registro conservan su comportamiento', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 824);
    addTearDown(tester.view.reset);
    final observer = LoginRouteObserver();
    await tester.pumpWidget(
      MaterialApp(home: const LoginPage(), navigatorObservers: [observer]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Google'));
    await tester.pumpAndSettle();
    expect(
      find.text('Aquí irá el inicio de sesión con Google.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final forgot = find.text('¿Olvidó su contraseña?');
    for (var i = 0; i < 5 && forgot.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }
    await tester.tap(forgot);
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final register = find.text('Registrarme');
    for (var i = 0; i < 5 && register.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }
    await tester.tap(register);
    // Comprobar el destino sin ampliar esta prueba al layout de Registro.
    final route = observer.lastPushed! as MaterialPageRoute<dynamic>;
    expect(
      route.builder(tester.element(find.byType(LoginPage))),
      isA<RegisterPage>(),
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'contraseña larga, visibilidad y botón accesible con teclado a 320px',
    (tester) async {
      const screen = Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screen;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pumpAndSettle();
      final field = loginField('Contraseña');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final password = List.filled(3, 'Solo_prueba_larga_123!').join();
      await tester.enterText(field, password);
      await tester.pumpAndSettle();
      expectAboveKeyboard(tester, field, screen, 300);
      expect(tester.widget<TextFormField>(field).controller!.text, password);
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();
      var editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.obscureText, isFalse);
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.obscureText, isTrue);
      expectAboveKeyboard(tester, field, screen, 300);
      final submit = find.widgetWithText(ElevatedButton, 'Iniciar Sesión');
      for (var i = 0; i < 5 && submit.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
        await tester.pumpAndSettle();
      }
      expect(submit.hitTestable(), findsOneWidget);
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(340));
      expect(
        editable.focusNode.hasFocus,
        isFalse,
        reason: 'Arrastrar permite ocultar el teclado',
      );
      tester.testTextInput.hide();
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(tester.getRect(waves).bottom, closeTo(screen.height, 0.01));
      expect(tester.widget<TextFormField>(field).controller!.text, password);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cambiar el foco con teclado abierto revela el campo nuevo', (
    tester,
  ) async {
    const screen = Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screen;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();
    await tester.tap(loginField('Correo electrónico'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    for (final hint in ['Contraseña', 'Correo electrónico']) {
      final field = loginField(hint);
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .requestFocus();
      await tester.pumpAndSettle();
      expectAboveKeyboard(tester, field, screen, 300);
    }
  });

  testWidgets('cerrar teclado conserva tamaños habituales y campos completos', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 824);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();
    final before = tester.getSize(loginField('Contraseña'));
    await tester.tap(loginField('Contraseña'));
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expectAboveKeyboard(
      tester,
      loginField('Contraseña'),
      const Size(400, 824),
      300,
    );
    tester.testTextInput.hide();
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    await tester.pumpAndSettle();
    expect(tester.getSize(loginField('Contraseña')), before);
    expect(tester.getRect(waves).bottom, closeTo(824, 0.01));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desmontar login tras enfocar no deja callbacks ni observadores activos',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pumpAndSettle();
      tester
          .widget<EditableText>(
            find.descendant(
              of: loginField('Correo electrónico'),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .requestFocus();
      await tester.pumpWidget(const SizedBox());
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final screen in [
    const Size(400, 824),
    const Size(320, 640),
    const Size(360, 800),
    const Size(400, 1000),
  ]) {
    testWidgets('ondas llegan al borde inferior en $screen con áreas seguras', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screen;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pumpAndSettle();
      expect(tester.getRect(waves).bottom, closeTo(screen.height, 0.01));
      expect(tester.getRect(waves).left, 0);
      expect(tester.getRect(waves).right, screen.width);
      final logo = tester.widget<Image>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName.endsWith(
                'Logo_Principal_AniMap.png',
              ),
        ),
      );
      expect(logo.height, 180);
      expect(tester.takeException(), isNull);
    });
  }

  for (final screen in [
    const Size(400, 824),
    const Size(320, 640),
    const Size(360, 800),
  ]) {
    for (final hint in ['Correo electrónico', 'Contraseña']) {
      testWidgets(
        '$hint se mantiene visible automáticamente con teclado en $screen',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = screen;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(const MaterialApp(home: LoginPage()));
          await tester.pumpAndSettle();
          final field = loginField(hint);
          if (field.hitTestable().evaluate().isEmpty) {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -140),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(field);
          await tester.pumpAndSettle();
          // Simula la apertura progresiva del IME después de recibir el foco.
          // El test no desplaza el formulario ni usa ensureVisible.
          for (final height in [100.0, 220.0, 300.0]) {
            tester.view.padding = const FakeViewPadding(top: 24);
            tester.view.viewInsets = FakeViewPadding(bottom: height);
            await tester.pump(const Duration(milliseconds: 40));
          }
          await tester.pumpAndSettle();
          expectAboveKeyboard(tester, field, screen, 300);
          final editable = tester.widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(editable.focusNode.hasFocus, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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

  testWidgets(
    'contraseña enfocada sigue visible al reducir la altura con teclado abierto',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 824);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      await tester.pumpAndSettle();
      final field = loginField('Contraseña');
      await tester.tap(field);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      expectAboveKeyboard(tester, field, const Size(320, 640), 300);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tocar fuera del formulario retira el foco del correo', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 824);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();
    final field = loginField('Correo electrónico');
    await tester.tap(field);
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    await tester.tap(find.text('Iniciar Sesión').first);
    await tester.pumpAndSettle();
    expect(editable.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
