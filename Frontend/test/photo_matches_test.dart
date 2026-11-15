import 'dart:async';
import 'package:animap/features/report/data/reports_service.dart';
import 'package:animap/features/report/presentation/pages/own_report_detail_page.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/authenticated_http_client.dart';
import 'package:animap/features/report/data/photo_matches_service.dart';
import 'package:animap/features/report/presentation/pages/photo_matches_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'image_recognition_test.dart' show bytes;
import 'package:animap/features/auth/data/session_storage.dart';

class MemoryStorage implements SessionStorage {
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

void main() {
  test(
    'history uses private cursor endpoint, rejects malformed scores, image uses fixed authorized path',
    () async {
      final session = SessionManager(storage: MemoryStorage());
      final paths = <String>[];
      final client = AuthenticatedHttpClient(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          paths.add(request.url.toString());
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(bytes, 200);
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': request.url.path.endsWith('/12')
                  ? {'id': 12, 'similarity': 9}
                  : [
                      {
                        'id': 12,
                        'similarity': .96,
                        'pet': {'name': 'Luna'},
                      },
                    ],
            }),
            200,
          );
        }),
        sessionManager: session,
      );
      // An authenticated fixture prevents any refresh or external request.
      await session.establishSession(
        accessToken: 'fixture',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      final service = PhotoMatchesService(client: client);
      final history = await service.list(before: 21);
      expect(history.single.id, 12);
      expect(history.single.similarity, .96);
      expect(
        paths.single,
        'http://example.invalid/api/recognition/matches?before=21',
      );
      expect(await service.image(12), bytes);
      expect(
        paths.last,
        'http://example.invalid/api/recognition/matches/12/image',
      );
      await expectLater(
        service.detail(12),
        throwsA(isA<PhotoMatchesException>()),
      );
    },
  );

  testWidgets(
    'history empty and failure support retry without displaying stale items',
    (tester) async {
      final session = SessionManager(storage: MemoryStorage());
      await session.establishSession(
        accessToken: 'fixture',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoMatchesPage(
            sessionManager: session,
            loader: (_) async {
              if (fail) throw Exception('offline');
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Aún no tienes coincidencias fotográficas.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'detail distinguishes original sighting date from later analysis event',
    (tester) async {
      final session = SessionManager(storage: MemoryStorage());
      await session.establishSession(
        accessToken: 'fixture',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoMatchDetailPage(
            matchId: 12,
            sessionManager: session,
            loader: (_) async => PhotoMatch.fromJson({
              'id': 12,
              'similarity': .91,
              'pet': {'name': 'Luna'},
              'observedAt': '2026-11-07T19:10:00.000Z',
              'createdAt': '2026-11-08T09:30:00.000Z',
            }),
            imageLoader: (_) async => throw Exception('Photo unavailable'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Fecha del avistamiento: 2026-11-07T19:10:00.000Z'),
        findsOneWidget,
      );
      expect(
        find.text('Fecha del evento: 2026-11-08T09:30:00.000Z'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'changing account clears private detail and ignores a late image response',
    (tester) async {
      final session = SessionManager(storage: MemoryStorage());
      await session.establishSession(
        accessToken: 'account-one',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      final ready = Completer<Uint8List>();
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoMatchDetailPage(
            matchId: 12,
            sessionManager: session,
            loader: (_) async => PhotoMatch.fromJson({
              'id': 12,
              'similarity': .91,
              'pet': {'name': 'Luna'},
              'reporter': {'label': 'Ana', 'phone': '3001234567'},
            }),
            imageLoader: (_) => ready.future,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Luna'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Teléfono compartido: 3001234567'),
        120,
      );
      expect(find.text('Teléfono compartido: 3001234567'), findsOneWidget);
      await session.establishSession(
        accessToken: 'account-two',
        refreshToken: 'other',
        role: 'USUARIO',
      );
      await tester.pump();
      expect(find.text('Luna'), findsNothing);
      expect(find.text('Teléfono compartido: 3001234567'), findsNothing);
      ready.complete(bytes);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Luna'), findsNothing);
    },
  );
  testWidgets(
    'detail authorization completing after account change cannot load image',
    (tester) async {
      final session = SessionManager(storage: MemoryStorage());
      await session.establishSession(
        accessToken: 'one',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      final ready = Completer<PhotoMatch>();
      var images = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoMatchDetailPage(
            matchId: 12,
            sessionManager: session,
            loader: (_) => ready.future,
            imageLoader: (_) async {
              images++;
              return bytes;
            },
          ),
        ),
      );
      await session.establishSession(
        accessToken: 'two',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      ready.complete(
        PhotoMatch.fromJson({
          'id': 12,
          'similarity': .91,
          'pet': {'name': 'Private'},
        }),
      );
      await tester.pumpAndSettle();
      expect(images, 0);
      expect(find.text('Private'), findsNothing);
    },
  );

  testWidgets(
    'match opens its authorized report and hides report on account switch',
    (tester) async {
      final session = SessionManager(storage: MemoryStorage());
      await session.establishSession(
        accessToken: 'one',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      int? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: PhotoMatchDetailPage(
            matchId: 12,
            sessionManager: session,
            loader: (_) async => PhotoMatch.fromJson({
              'id': 12,
              'reportId': 27,
              'similarity': .91,
              'pet': {'name': 'Luna'},
            }),
            imageLoader: (_) async => bytes,
            reportLoader: (id) async {
              opened = id;
              return const OwnReportDetails(report: {}, pet: {}, photos: []);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('match-open-report')),
        180,
      );
      await tester.tap(find.byKey(const ValueKey('match-open-report')));
      await tester.pumpAndSettle();
      expect(opened, 27);
      expect(find.byType(OwnReportDetailPage), findsOneWidget);
      await session.establishSession(
        accessToken: 'two',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      await tester.pumpAndSettle();
      expect(find.byType(OwnReportDetailPage), findsNothing);
    },
  );
  testWidgets(
    'private detail fits 320px with larger text and omitted contact',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = SessionManager(storage: MemoryStorage());
      await session.establishSession(
        accessToken: 'one',
        refreshToken: 'fixture',
        role: 'USUARIO',
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: PhotoMatchDetailPage(
            matchId: 12,
            sessionManager: session,
            loader: (_) async => PhotoMatch.fromJson({
              'id': 12,
              'reportId': 27,
              'similarity': .91,
              'pet': {'name': 'Luna nombre largo para comprobar la pantalla'},
              'reporter': {'label': 'Persona de la comunidad'},
              'location': {'lat': 4.65, 'lng': -74.10, 'method': 'MAPA'},
            }),
            imageLoader: (_) async => bytes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('El reportante no compartió su teléfono.'),
        160,
      );
      expect(
        find.text('El reportante no compartió su teléfono.'),
        findsOneWidget,
      );
      expect(find.textContaining('Teléfono compartido:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
