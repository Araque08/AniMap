import 'dart:convert';
import 'dart:async';
import 'package:animap/features/auth/data/session_manager.dart';
import 'package:animap/features/auth/data/session_storage.dart';
import 'package:animap/features/notifications/push_notification_coordinator.dart';
import 'package:animap/features/report/data/reports_service.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late SessionManager session;
  late PushNotificationCoordinator coordinator;
  late List<int> opened;
  late int banners;
  late int loads;
  late Future<OwnReportDetails> Function(int) load;
  late Future<Map<String, dynamic>> Function(int) history;
  final data = <String, dynamic>{
    'type': 'AVISTAMIENTO_VINCULADO',
    'reportId': '8',
    'sightingId': '41',
    'notificationId': '1',
    'ownerId': '7',
  };
  Future<void> login(int id) => session.establishSession(
    accessToken:
        'fixture.${base64UrlEncode(utf8.encode(jsonEncode({'sub': id})))}.signature',
    refreshToken: 'fixture-refresh',
    role: 'USUARIO',
  );
  setUp(() {
    session = SessionManager(
      storage: _Storage(),
      authBaseUrl: 'http://example.invalid/api/auth',
    );
    opened = [];
    banners = 0;
    loads = 0;
    load = (_) async {
      loads++;
      return const OwnReportDetails(report: {}, pet: {}, photos: []);
    };
    history = (_) async => {
      'sightings': [
        {'id': 41},
      ],
    };
    coordinator = PushNotificationCoordinator(
      session: session,
      loadReport: (id) => load(id),
      loadHistory: (id) => history(id),
      onOpen: (id, sightingId) => opened.addAll([id, sightingId]),
      onForeground: (_, _) => banners++,
    );
  });
  tearDown(() {
    coordinator.dispose();
    session.dispose();
  });

  test(
    'foreground respects permission and owner and deduplicates alerts',
    () async {
      await login(7);
      coordinator.foreground(data, allowed: false);
      coordinator.foreground({...data, 'ownerId': '8'}, allowed: true);
      expect(banners, 0);
      coordinator.foreground(data, allowed: true);
      coordinator.foreground(data, allowed: true);
      expect(banners, 1);
      expect(loads, 0);
    },
  );
  test(
    'tap waits for restoration then loads the private report once',
    () async {
      coordinator.tap(data);
      expect(opened, isEmpty);
      await login(7);
      await coordinator.pending;
      coordinator.tap(data);
      await coordinator.pending;
      expect(opened, [8, 41]);
      expect(loads, 1);
    },
  );
  test(
    'other account and malformed payload cannot navigate or request data',
    () async {
      await login(8);
      coordinator.tap(data);
      await coordinator.pending;
      for (final entry in [
        {'reportId': '-1'},
        {'type': 'unknown'},
        {'reportId': '8.5'},
      ]) {
        coordinator.tap({...data, ...entry});
      }
      await coordinator.pending;
      expect(opened, isEmpty);
      expect(loads, 0);
    },
  );
  test('destination survives login with a different account', () async {
    coordinator.tap(data);
    await login(8);
    await coordinator.pending;
    expect(loads, 0);
    await login(7);
    await coordinator.pending;
    expect(opened, [8, 41]);
  });
  test('destination is cleared by explicit logout', () async {
    coordinator.tap(data);
    await session.logout();
    await login(7);
    await coordinator.pending;
    expect(opened, isEmpty);
  });
  test(
    'account change while report loads cannot open the previous users report',
    () async {
      final result = Completer<OwnReportDetails>();
      load = (_) => result.future;
      history = (_) async => {
        'sightings': [
          {'id': 41},
        ],
      };
      await login(7);
      coordinator.tap(data);
      await Future<void>.delayed(Duration.zero);
      await login(8);
      result.complete(const OwnReportDetails(report: {}, pet: {}, photos: []));
      await coordinator.pending;
      expect(opened, isEmpty);
    },
  );
  test('private report failure is contained and does not navigate', () async {
    load = (_) async => throw ReportsException('No disponible');
    await login(7);
    coordinator.tap(data);
    await coordinator.pending;
    expect(opened, isEmpty);
    expect(session.isAuthenticated, isTrue);
  });
  test(
    'missing sighting in authorized history does not open another item',
    () async {
      history = (_) async => {'sightings': <Map<String, dynamic>>[]};
      await login(7);
      coordinator.tap(data);
      await coordinator.pending;
      expect(opened, isEmpty);
    },
  );
}
