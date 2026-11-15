import 'dart:async';
import 'dart:convert';

import 'package:animap/app.dart';
import 'package:animap/config/firebase_setup.dart';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/notifications/presentation/pages/notifications_page.dart';
import 'package:animap/features/report/presentation/pages/photo_matches_page.dart';
import 'package:animap/features/report/presentation/pages/report_search_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Storage implements SessionStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Session extends SessionManager {
  _Session() : super(storage: _Storage());
  @override
  Future<void> bootstrap() async {} // Keep the synthetic session; no API refresh.
}

class _Firebase extends FirebaseSetup {
  _Firebase() : super(isAndroid: false);
  final foreground = StreamController<RemoteMessage>.broadcast(sync: true);
  final opened = StreamController<RemoteMessage>.broadcast(sync: true);
  @override
  Stream<RemoteMessage> get foregroundMessages => foreground.stream;
  @override
  Stream<RemoteMessage> get openedMessages => opened.stream;
  @override
  Future<bool> notificationsAllowed() async => true;
  @override
  Future<void> registerMessaging() async {}
  @override
  Future<void> dispose() async {
    await foreground.close();
    await opened.close();
  }
}

void main() {
  final seen = <String>[];
  final client = MockClient((request) async {
    seen.add('${request.method} ${request.url.path}');
    if (request.method != 'GET') {
      throw StateError('Read-only notification fixture');
    }
    if (request.url.path.endsWith('/notifications')) {
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {
            'pagina': 1,
            'hayMas': false,
            'notificaciones': [
              {
                'id': 501,
                'titulo': 'Aviso administrativo de prueba',
                'mensaje': 'Mensaje sintético',
                'tipo': 'ADMINISTRATIVA',
                'fecha': '2026-11-15T12:00:00Z',
                'leida': true,
              },
            ],
          },
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/recognition/matches/12/image')) {
      return http.Response('', 404);
    }
    if (request.url.path.endsWith('/recognition/matches/12')) {
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {
            'id': 12,
            'reportId': 8,
            'sightingId': 41,
            'similarity': .91,
            'pet': {'name': 'Coincidencia sintética'},
          },
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/map/reports')) {
      return http.Response(
        jsonEncode({'ok': true, 'data': [], 'total': 0}),
        200,
      );
    }
    throw StateError('Unexpected isolated URL: ${request.url.path}');
  });
  late _Session session;
  late _Firebase firebase;
  final token =
      'fixture.${base64UrlEncode(utf8.encode(jsonEncode({'sub': 7})))}.signature';
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    seen.clear();
    session = _Session();
    firebase = _Firebase();
    await session.establishSession(
      accessToken: token,
      refreshToken: 'fixture',
      role: 'ADMINISTRADOR',
    );
    await SessionManager.instance.establishSession(
      accessToken: token,
      refreshToken: 'fixture',
      role: 'ADMINISTRADOR',
    );
  });

  Future<void> run(WidgetTester tester, Future<void> Function() action) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    try {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          AniMapApp(sessionManager: session, firebase: firebase),
        );
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pumpAndSettle();
        await action();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pumpAndSettle();
      }, () => client);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await firebase.dispose();
      session.dispose();
      await tester.runAsync(() => SessionManager.instance.clearLocalSession());
      await tester.binding.setSurfaceSize(null);
    }
  }

  testWidgets(
    'administrative tap opens its history item without invoking photo recognition',
    (tester) async {
      await run(tester, () async {
        firebase.opened.add(
          const RemoteMessage(
            data: {'type': 'ADMINISTRATIVA', 'notificationId': '501'},
          ),
        );
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NotificationsPage>(find.byType(NotificationsPage))
              .initialNotificationId,
          501,
        );
        expect(find.text('Aviso administrativo de prueba'), findsWidgets);
        expect(seen.any((url) => url.contains('/recognition/')), isFalse);
      });
    },
  );

  testWidgets(
    'administrative foreground action opens the notification history',
    (tester) async {
      await run(tester, () async {
        firebase.foreground.add(
          const RemoteMessage(
            data: {'type': 'ADMINISTRATIVA', 'notificationId': '501'},
            notification: RemoteNotification(
              title: 'Aviso administrativo de prueba',
              body: 'Mensaje sintético',
            ),
          ),
        );
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(MaterialBanner), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Ver'));
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsPage), findsOneWidget);
      });
    },
  );

  testWidgets(
    'photographic tap keeps its private detail instead of administrative history',
    (tester) async {
      await run(tester, () async {
        firebase.opened.add(
          const RemoteMessage(
            data: {
              'type': 'COINCIDENCIA_FOTOGRAFICA',
              'notificationId': '502',
              'matchId': '12',
              'reportId': '8',
              'sightingId': '41',
              'ownerId': '7',
            },
          ),
        );
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(PhotoMatchDetailPage), findsOneWidget);
        expect(find.text('Coincidencia sintética'), findsOneWidget);
        expect(find.byType(NotificationsPage), findsNothing);
      });
    },
  );

  testWidgets('community tap keeps Reportar y Buscar as its destination', (
    tester,
  ) async {
    await run(tester, () async {
      firebase.opened.add(
        const RemoteMessage(
          data: {
            'type': 'PERDIDA_CERCANA',
            'notificationId': '503',
            'reportId': '8',
            'recipientId': '7',
          },
        ),
      );
      tester.binding.scheduleFrame();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(ReportarBuscarPage), findsOneWidget);
      expect(find.byType(NotificationsPage), findsNothing);
      expect(seen.any((url) => url.contains('/recognition/')), isFalse);
    });
  });
}
