import 'dart:convert';

import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/presentation/pages/login_page.dart';
import 'package:animap/features/auth/presentation/session_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _HomeProbe extends StatefulWidget {
  const _HomeProbe(this.onCreated);
  final VoidCallback onCreated;
  @override
  State<_HomeProbe> createState() => _HomeProbeState();
}

class _HomeProbeState extends State<_HomeProbe> {
  @override
  void initState() {
    super.initState();
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Home único'));
}

void main() {
  testWidgets('login desde SessionGate crea un solo destino autenticado', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final manager = SessionManager.instance;
    await manager.clearLocalSession();
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var created = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: SessionGate(
              sessionManager: manager,
              authenticatedBuilder: (_) => _HomeProbe(() => created++),
            ),
            routes: {'/home': (_) => _HomeProbe(() => created++)},
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Correo electrónico'),
          'navigation@example.invalid',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Contraseña'),
          'isolated-test',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar Sesión'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsNothing);
        expect(find.text('Home único'), findsOneWidget);
        expect(
          created,
          1,
          reason: 'No crear/destruir dos mapas nativos al entrar',
        );
        expect(tester.takeException(), isNull);
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'accessToken': 'test-access',
              'refreshToken': 'test-refresh',
              'user': {'nombre': 'Prueba', 'rol': 'USUARIO'},
            },
          }),
          200,
        ),
      ),
    );
  });
}
