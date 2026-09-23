import 'dart:typed_data';

import 'package:animap/features/user/presentation/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

Map<String, dynamic> profile(String? photo) => {
  'nombre': 'Usuario temporal',
  'email': 'temporal@animap.invalid',
  'telefono': '3000000000',
  'foto_url': photo,
  'notificaciones_activas': true,
};

const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

XFile validPng(String name) => XFile.fromData(
  Uint8List.fromList([...pngSignature, 0, 0, 0, 0]),
  path: name,
  mimeType: 'image/png',
);

void main() {
  testWidgets('previsualiza, sube y conserva la foto al volver a entrar', (
    tester,
  ) async {
    const newPath = '/api/profile/photo/507f1f77bcf86cd799439011';
    var uploads = 0;

    Widget page({String? initialPhoto}) => MaterialApp(
      home: ProfilePage(
        profileLoader: () async => profile(initialPhoto),
        photoPicker: () async => validPng('perfil.png'),
        photoUploader: (_) async {
          uploads++;
          return profile(newPath);
        },
      ),
    );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    expect(find.text('Previsualizar foto'), findsOneWidget);
    expect(uploads, 0);
    await tester.tap(find.text('Usar esta foto'));
    await tester.pumpAndSettle();
    expect(uploads, 1);

    final updatedAvatar = tester
        .widgetList<CircleAvatar>(find.byType(CircleAvatar))
        .where((avatar) => avatar.backgroundImage is NetworkImage)
        .single;
    expect(
      (updatedAvatar.backgroundImage as NetworkImage).url,
      endsWith(newPath),
    );

    await tester.pumpWidget(page(initialPhoto: newPath));
    await tester.pumpAndSettle();
    final reloadedAvatar = tester
        .widgetList<CircleAvatar>(find.byType(CircleAvatar))
        .where((avatar) => avatar.backgroundImage is NetworkImage)
        .single;
    expect(
      (reloadedAvatar.backgroundImage as NetworkImage).url,
      endsWith(newPath),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelar previsualización conserva la foto anterior', (
    tester,
  ) async {
    const oldPath = '/api/profile/photo/507f1f77bcf86cd799439010';
    var uploads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          profileLoader: () async => profile(oldPath),
          photoPicker: () async => validPng('nueva.png'),
          photoUploader: (_) async {
            uploads++;
            return profile('/new');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(uploads, 0);
    final avatar = tester
        .widgetList<CircleAvatar>(find.byType(CircleAvatar))
        .where((item) => item.backgroundImage is NetworkImage)
        .single;
    expect((avatar.backgroundImage as NetworkImage).url, endsWith(oldPath));
  });

  testWidgets('Elegir otra abre selector otra vez y sube la segunda', (
    tester,
  ) async {
    var picks = 0;
    var uploadedName = '';
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          profileLoader: () async => profile(null),
          photoPicker: () async {
            picks++;
            return validPng(picks == 1 ? 'primera.png' : 'segunda.png');
          },
          photoUploader: (image) async {
            uploadedName = image.name;
            return profile('/api/profile/photo/new');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir otra'));
    await tester.pumpAndSettle();
    expect(picks, 2);
    expect(find.text('Previsualizar foto'), findsOneWidget);
    await tester.tap(find.text('Usar esta foto'));
    await tester.pumpAndSettle();
    expect(uploadedName, 'segunda.png');
  });

  testWidgets('rechaza foto mayor de 5 MB antes del upload', (tester) async {
    var uploads = 0;
    final bytes = Uint8List(5 * 1024 * 1024 + 1);
    bytes.setRange(0, pngSignature.length, pngSignature);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          profileLoader: () async => profile(null),
          photoPicker: () async => XFile.fromData(bytes, path: 'grande.png'),
          photoUploader: (_) async {
            uploads++;
            return profile('/new');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    expect(find.textContaining('superar el máximo de 5 MB'), findsOneWidget);
    expect(find.text('Previsualizar foto'), findsNothing);
    expect(uploads, 0);
  });

  testWidgets('rechaza formato inválido antes del upload', (tester) async {
    var uploads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          profileLoader: () async => profile(null),
          photoPicker: () async => XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            path: 'archivo.gif',
          ),
          photoUploader: (_) async {
            uploads++;
            return profile('/new');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    expect(find.textContaining('formato no permitido'), findsOneWidget);
    expect(uploads, 0);
  });

  testWidgets('ProfilePage responde a 320 px y muestra datos reales', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ProfilePage(profileLoader: () async => profile(null))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Usuario temporal'), findsOneWidget);
    expect(find.text('temporal@animap.invalid'), findsOneWidget);
    expect(find.text('Información Personal'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Eliminar cuenta'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Eliminar cuenta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
