import 'dart:async';

import 'package:animap/config/firebase_setup.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends Fake implements NotificationSettings {
  _Settings(this.authorizationStatus);

  @override
  final AuthorizationStatus authorizationStatus;
}

class _Messaging extends Fake implements FirebaseMessaging {
  final registrations = StreamController<String>.broadcast(sync: true);
  AuthorizationStatus permission = AuthorizationStatus.authorized;
  int permissionRequests = 0;
  int registerCalls = 0;
  bool listeningBeforeRegister = false;
  bool failRegistration = false;

  @override
  Stream<String> get onRegistered => registrations.stream;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    permissionRequests++;
    return _Settings(permission);
  }

  @override
  Future<void> register({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async {
    registerCalls++;
    listeningBeforeRegister = registrations.hasListener;
    if (failRegistration) throw Exception('private-registration-id');
    registrations.add('private-registration-id');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Messaging messaging;
  late FirebaseSetup setup;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;
  var initializeCalls = 0;

  setUp(() {
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    initializeCalls = 0;
    messaging = _Messaging();
    setup = FirebaseSetup(
      isAndroid: true,
      initializeFirebase: () async => initializeCalls++,
      messaging: () => messaging,
    );
  });

  tearDown(() async {
    await setup.dispose();
    await messaging.registrations.close();
    debugPrint = originalDebugPrint;
  });

  test('Android inicializa Firebase una sola vez', () async {
    expect(await setup.initialize(), isTrue);
    expect(await setup.initialize(), isTrue);
    expect(initializeCalls, 1);
  });

  test(
    'otras plataformas no inicializan Firebase ni solicitan permiso',
    () async {
      await setup.dispose();
      setup = FirebaseSetup(
        isAndroid: false,
        initializeFirebase: () async => initializeCalls++,
        messaging: () => messaging,
      );
      expect(await setup.initialize(), isFalse);
      await setup.registerMessaging();
      expect(initializeCalls, 0);
      expect(messaging.permissionRequests, 0);
      expect(messaging.registerCalls, 0);
    },
  );

  test(
    'permiso concedido registra con listener previo sin exponer el ID',
    () async {
      await setup.initialize();
      await setup.registerMessaging();
      expect(messaging.permissionRequests, 1);
      expect(messaging.registerCalls, 1);
      expect(messaging.listeningBeforeRegister, isTrue);
      expect(logs, contains('FCM Android: registration ready.'));
      expect(logs.join(), isNot(contains('private-registration-id')));
    },
  );

  test('permiso denegado no registra ni deja listeners', () async {
    messaging.permission = AuthorizationStatus.denied;
    await setup.initialize();
    await setup.registerMessaging();
    expect(messaging.registerCalls, 0);
    expect(messaging.registrations.hasListener, isFalse);
    expect(logs, contains('FCM Android: notification permission not granted.'));
  });

  test(
    'entrega el identificador inicial y sus cambios sin publicarlos en logs',
    () async {
      await setup.dispose();
      final received = <String>[];
      setup = FirebaseSetup(
        isAndroid: true,
        initializeFirebase: () async {},
        messaging: () => messaging,
        onRegistration: received.add,
      );
      await setup.initialize();
      await setup.registerMessaging();
      messaging.registrations.add('fixture-fid-renewed');
      expect(received.length, 2);
      expect(logs.join(), isNot(contains('fixture-fid-renewed')));
      expect(logs.join(), isNot(contains('private-registration-id')));
    },
  );

  test('fallo de inicializacion no lanza ni inicia Messaging', () async {
    await setup.dispose();
    setup = FirebaseSetup(
      isAndroid: true,
      initializeFirebase: () async => throw Exception('private-api-key'),
      messaging: () => messaging,
    );
    expect(await setup.initialize(), isFalse);
    await setup.registerMessaging();
    expect(messaging.permissionRequests, 0);
    expect(logs.join(), isNot(contains('private-api-key')));
  });

  test('fallo de registro se contiene sin exponer credenciales', () async {
    messaging.failRegistration = true;
    await setup.initialize();
    await setup.registerMessaging();
    expect(messaging.registerCalls, 1);
    expect(logs, contains('FCM Android: registration unavailable.'));
    expect(logs.join(), isNot(contains('private-registration-id')));
  });

  test('invocaciones repetidas no duplican permiso ni registro', () async {
    await setup.initialize();
    await Future.wait([setup.registerMessaging(), setup.registerMessaging()]);
    expect(messaging.permissionRequests, 1);
    expect(messaging.registerCalls, 1);
  });

  test(
    'errores del stream se contienen y dispose libera el listener',
    () async {
      await setup.initialize();
      await setup.registerMessaging();
      messaging.registrations.addError(Exception('private-registration-id'));
      expect(logs, contains('FCM Android: registration unavailable.'));
      expect(logs.join(), isNot(contains('private-registration-id')));
      await setup.dispose();
      expect(messaging.registrations.hasListener, isFalse);
    },
  );
}
