import 'dart:async';

import 'package:animap/features/user/data/account_settings_service.dart';
import 'package:animap/features/user/presentation/pages/profile_options_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const defaults = NotificationPreferencesData(
  notificationsEnabled: true,
  onlyMyZone: false,
  species: null,
  eventType: null,
  radiusKm: 2,
);

Future<void> selectOption(WidgetTester tester, Key key, String option) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> tapSave(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('save-notification-preferences'));
  await tester.scrollUntilVisible(
    button,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(button);
}

void main() {
  group('Preferencias de notificación', () {
    testWidgets('carga datos reales y muestra loading sin inventar defaults', (
      tester,
    ) async {
      final completer = Completer<NotificationPreferencesData>();
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPreferencesPage(loader: () => completer.future),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notification-preferences-form')),
        findsNothing,
      );

      completer.complete(defaults);
      await tester.pumpAndSettle();
      expect(find.text('Todas'), findsWidgets);
      expect(find.text('2 km'), findsOneWidget);
      expect(find.text('Ave'), findsNothing);
    });

    testWidgets('sin cambios o valor equivalente hace 0 PATCH', (tester) async {
      var patches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPreferencesPage(
            loader: () async => defaults,
            updater: (value) async {
              patches++;
              return value;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();
      expect(patches, 0);
      expect(find.text('No realizaste cambios.'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(NotificationPreferencesPage)),
      ).removeCurrentSnackBar(reason: SnackBarClosedReason.remove);
      await tester.pumpAndSettle();

      await selectOption(
        tester,
        const ValueKey('notification-species'),
        'Gato',
      );
      await selectOption(
        tester,
        const ValueKey('notification-species'),
        'Todas',
      );
      await tapSave(tester);
      await tester.pump();
      expect(patches, 0);
    });

    testWidgets('guarda todos los campos con exactamente un PATCH y conserva', (
      tester,
    ) async {
      var patches = 0;
      var stored = defaults;
      Widget page(Key key) => MaterialApp(
        key: key,
        home: NotificationPreferencesPage(
          loader: () async => stored,
          updater: (value) async {
            patches++;
            stored = value;
            return value;
          },
        ),
      );

      await tester.pumpWidget(page(const ValueKey('first-load')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('only-my-zone')));
      await tester.pumpAndSettle();
      await selectOption(
        tester,
        const ValueKey('notification-species'),
        'Gato',
      );
      await selectOption(
        tester,
        const ValueKey('notification-event'),
        'Encontrado',
      );
      await selectOption(tester, const ValueKey('notification-radius'), '5 km');
      await tester.tap(find.byKey(const ValueKey('notifications-enabled')));
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(patches, 1);
      expect(stored.notificationsEnabled, false);
      expect(stored.onlyMyZone, true);
      expect(stored.species, 'Gato');
      expect(stored.eventType, 'ENCONTRADO');
      expect(stored.radiusKm, 5);
      expect(
        find.text('Preferencias guardadas correctamente.'),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(NotificationPreferencesPage)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      await tapSave(tester);
      await tester.pump();
      expect(patches, 1);

      await tester.pumpWidget(page(const ValueKey('second-load')));
      await tester.pumpAndSettle();
      expect(find.text('Gato'), findsOneWidget);
      expect(find.text('Encontrado'), findsOneWidget);
      expect(find.text('5 km'), findsOneWidget);
    });

    testWidgets('error conserva estado y permite reintentar', (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPreferencesPage(
            loader: () async {
              attempts++;
              if (attempts == 1) {
                throw const AccountSettingsException('Sin conexión');
              }
              return const NotificationPreferencesData(
                notificationsEnabled: true,
                onlyMyZone: true,
                species: 'Perro',
                eventType: 'PERDIDA',
                radiusKm: 1,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('Todas'), findsNothing);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Perro'), findsOneWidget);
      expect(find.text('1 km'), findsOneWidget);
    });

    testWidgets('error al guardar conserva cambios y permite reintentar', (
      tester,
    ) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPreferencesPage(
            loader: () async => defaults,
            updater: (value) async {
              attempts++;
              if (attempts == 1) {
                throw const AccountSettingsException('Red no disponible');
              }
              return value;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('only-my-zone')));
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text('Red no disponible'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('only-my-zone')))
            .value,
        true,
      );

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(
        find.text('Preferencias guardadas correctamente.'),
        findsOneWidget,
      );
    });
  });

  group('Sesiones activas', () {
    final now = DateTime.utc(2026, 9, 13, 12);
    late List<ActiveSessionData> sessions;

    setUp(() {
      sessions = [
        ActiveSessionData(
          id: 2,
          deviceId: '••••otro2',
          createdAt: now.subtract(const Duration(hours: 1)),
          expiresAt: now.add(const Duration(days: 30)),
          isCurrent: false,
        ),
        ActiveSessionData(
          id: 1,
          deviceId: '••••actual',
          createdAt: now.subtract(const Duration(days: 1)),
          expiresAt: now.add(const Duration(days: 29)),
          isCurrent: true,
        ),
      ];
    });

    testWidgets('lista sesión actual primero y otras sesiones reales', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ActiveSessionsPage(loader: () async => sessions)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Este dispositivo'), findsOneWidget);
      expect(find.text('Sesión actual'), findsOneWidget);
      expect(find.text('Otro dispositivo'), findsOneWidget);
      expect(find.text('••••otro2'), findsOneWidget);
      expect(find.byKey(const ValueKey('revoke-session-1')), findsNothing);
      expect(find.byKey(const ValueKey('revoke-session-2')), findsOneWidget);
    });

    testWidgets('cancelar no llama y confirmar elimina la otra sesión', (
      tester,
    ) async {
      var revocations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ActiveSessionsPage(
            loader: () async => sessions,
            revoker: (id) async {
              revocations++;
              expect(id, 2);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('revoke-session-2')));
      await tester.pumpAndSettle();
      expect(find.text('¿Cerrar esta sesión?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(revocations, 0);

      await tester.tap(find.byKey(const ValueKey('revoke-session-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-revoke-session')));
      await tester.pumpAndSettle();
      expect(revocations, 1);
      expect(find.text('Otro dispositivo'), findsNothing);
      expect(find.text('Este dispositivo'), findsOneWidget);
    });

    testWidgets('preferencias y sesiones no desbordan a 320 px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: ActiveSessionsPage(loader: () async => sessions)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPreferencesPage(loader: () async => defaults),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save-notification-preferences')),
        250,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
