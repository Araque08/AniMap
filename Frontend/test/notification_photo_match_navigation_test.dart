import 'dart:async';
import 'dart:convert';

import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/notifications/presentation/pages/notifications_page.dart';
import 'package:animap/features/notifications/data/notification_history_service.dart';
import 'package:animap/features/map/presentation/pages/map_page.dart';
import 'package:animap/features/report/presentation/pages/photo_matches_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Observer extends NavigatorObserver {
  Route<dynamic>? lastPushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
    super.didPush(route, previousRoute);
  }
}

void main() {
  final requests = <String>[];
  int? matchId;
  var detailStatus = 200;
  var alreadyRead = true;
  var sightingAvailable = true;
  Completer<http.Response>? delayedDetail;
  final observer = _Observer();
  final client = MockClient((request) async {
    requests.add('${request.method} ${request.url.path}');
    if (request.method == 'PATCH' && request.url.path.endsWith('/502/read')) {
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {'id': 502, 'leida': true},
        }),
        200,
      );
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
                'id': 502,
                'titulo': 'Coincidencia QA',
                'mensaje': 'Similitud: 91 %',
                'tipo': 'COINCIDENCIA_FOTOGRAFICA',
                'leida': alreadyRead,
                'fecha': '2026-11-15T12:00:00Z',
                'reporteId': 8,
                'avistamientoId': 41,
                'matchId': matchId,
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
      if (delayedDetail != null) return delayedDetail!.future;
      return http.Response(
        jsonEncode({
          'ok': detailStatus == 200,
          'data': {
            'id': 12,
            'similarity': .91,
            'sightingId': 41,
            'pet': {'name': 'Mascota QA privada'},
          },
        }),
        detailStatus,
      );
    }
    if (request.url.path.endsWith('/map/reports')) {
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': sightingAvailable
              ? [
                  {
                    'id': 'sighting_41',
                    'type': 'sighting',
                    'title': 'Avistamiento QA',
                    'lat': 4.65,
                    'lng': -74.1,
                  },
                ]
              : [],
        }),
        200,
      );
    }
    throw StateError('Unexpected fixture request: ${request.url.path}');
  });

  Future<void> establish(
    int userId,
  ) => SessionManager.instance.establishSession(
    accessToken:
        'fixture.${base64UrlEncode(utf8.encode(jsonEncode({'sub': userId})))}.signature',
    refreshToken: 'fixture',
    role: 'USUARIO',
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    requests.clear();
    matchId = 12;
    detailStatus = 200;
    alreadyRead = true;
    sightingAvailable = true;
    delayedDetail = null;
    await establish(7);
  });

  Future<void> run(
    WidgetTester tester,
    Future<void> Function() action, {
    bool allowsPublicSighting = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    try {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: const NotificationsPage(initialNotificationId: 502),
            navigatorObservers: [observer],
          ),
        );
        await tester.pumpAndSettle();
        await action();
        if (!allowsPublicSighting) {
          expect(requests.any((r) => r.contains('/map/')), isFalse);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }, () => client);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => SessionManager.instance.clearLocalSession());
      await tester.binding.setSurfaceSize(null);
    }
  }

  testWidgets('historial general abre el detalle privado de la coincidencia', (
    tester,
  ) async {
    await run(tester, () async {
      await tester.tap(find.text('Ver coincidencia'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoMatchDetailPage), findsOneWidget);
      expect(find.text('Mascota QA privada'), findsOneWidget);
      expect(requests, contains('GET /api/recognition/matches/12'));
    });
  });

  testWidgets('desde el detalle privado se abre el avistamiento existente', (
    tester,
  ) async {
    await run(tester, () async {
      await tester.tap(find.text('Ver coincidencia'));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('match-open-sighting'));
      await tester.scrollUntilVisible(button, 120);
      await tester.tap(button);
      await tester.idle();
      final context = tester.element(find.byType(PhotoMatchDetailPage));
      final route = observer.lastPushed! as MaterialPageRoute<void>;
      final guarded = route.builder(context) as ListenableBuilder;
      final detail = guarded.builder(context, null) as SightingDetailPage;
      expect(detail.report.id, 'sighting_41');
      expect(
        requests.where((r) => r == 'GET /api/recognition/matches/12').length,
        greaterThanOrEqualTo(3),
      );
      expect(requests, contains('GET /api/map/reports'));
    }, allowsPublicSighting: true);
  });

  testWidgets('sin matchId no recurre al mapa ni inventa identificadores', (
    tester,
  ) async {
    matchId = null;
    await run(tester, () async {
      await tester.tap(find.text('Ver coincidencia'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoMatchDetailPage), findsNothing);
      expect(requests.any((r) => r.contains('/recognition/')), isFalse);
      expect(
        find.text(
          'El detalle privado de esta coincidencia no está disponible.',
        ),
        findsOneWidget,
      );
    });
  });

  test(
    'matchId solo acepta enteros positivos de notificaciones fotográficas',
    () {
      final base = {
        'id': 502,
        'tipo': 'COINCIDENCIA_FOTOGRAFICA',
        'fecha': '2026-11-15T12:00:00Z',
      };
      for (final invalid in [null, 0, -1, 12.5, '12', 2147483648]) {
        expect(
          AnimapNotification.fromJson({...base, 'matchId': invalid}).matchId,
          isNull,
        );
      }
      expect(AnimapNotification.fromJson({...base, 'matchId': 12}).matchId, 12);
      expect(
        AnimapNotification.fromJson({
          ...base,
          'tipo': 'ADMINISTRATIVA',
          'matchId': 12,
        }).matchId,
        isNull,
      );
    },
  );

  testWidgets('marcar como leída conserva el acceso a la coincidencia', (
    tester,
  ) async {
    alreadyRead = false;
    await run(tester, () async {
      expect(requests, contains('PATCH /api/notifications/502/read'));
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coincidencia QA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver coincidencia'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoMatchDetailPage), findsOneWidget);
    });
  });

  testWidgets(
    'el acceso al avistamiento vuelve a verificar la autorización privada',
    (tester) async {
      await run(tester, () async {
        await tester.tap(find.text('Ver coincidencia'));
        await tester.pumpAndSettle();
        detailStatus = 404;
        final button = find.byKey(const ValueKey('match-open-sighting'));
        await tester.scrollUntilVisible(button, 120);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(SightingDetailPage), findsNothing);
        expect(requests.any((r) => r.contains('/map/')), isFalse);
      });
    },
  );

  testWidgets(
    'un avistamiento retirado no se reconstruye con información antigua',
    (tester) async {
      sightingAvailable = false;
      await run(tester, () async {
        await tester.tap(find.text('Ver coincidencia'));
        await tester.pumpAndSettle();
        final button = find.byKey(const ValueKey('match-open-sighting'));
        await tester.scrollUntilVisible(button, 120);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(SightingDetailPage), findsNothing);
        expect(
          find.text('El avistamiento ya no está disponible.'),
          findsOneWidget,
        );
      }, allowsPublicSighting: true);
    },
  );

  testWidgets(
    'una coincidencia no autorizada no abre otra ruta como alternativa',
    (tester) async {
      detailStatus = 404;
      await run(tester, () async {
        await tester.tap(find.text('Ver coincidencia'));
        await tester.pumpAndSettle();
        expect(find.byType(PhotoMatchDetailPage), findsNothing);
        expect(requests, contains('GET /api/recognition/matches/12'));
      });
    },
  );

  testWidgets(
    'una autorización tardía no navega después de cambiar de cuenta',
    (tester) async {
      delayedDetail = Completer<http.Response>();
      await run(tester, () async {
        await tester.tap(find.text('Ver coincidencia'));
        await tester.pump();
        await tester.runAsync(() => establish(8));
        delayedDetail!.complete(
          http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'id': 12,
                'similarity': .91,
                'pet': {'name': 'Cuenta anterior'},
              },
            }),
            200,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PhotoMatchDetailPage), findsNothing);
        expect(requests.any((r) => r.endsWith('/image')), isFalse);
      });
    },
  );
}
