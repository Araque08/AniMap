import 'package:animap/features/pet/presentation/pages/my_pets_page.dart';
import 'package:animap/features/pet/presentation/pages/register_pet_page.dart';
import 'package:animap/features/user/presentation/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final profile = {
    'nombre': 'Usuario temporal',
    'email': 'temporal@animap.invalid',
    'telefono': '3000000000',
    'foto_url': null,
  };

  testWidgets('Perfil muestra Mis Mascotas en orden y vuelve desde la lista', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfilePage(profileLoader: () async => profile)),
    );
    await tester.pumpAndSettle();

    final personal = find.text('Información Personal');
    final pets = find.text('Mis Mascotas');
    final sessions = find.text('Sesiones activas');
    expect(pets, findsOneWidget);
    expect(
      tester.getTopLeft(personal).dy,
      lessThan(tester.getTopLeft(pets).dy),
    );
    expect(
      tester.getTopLeft(pets).dy,
      lessThan(tester.getTopLeft(sessions).dy),
    );

    await tester.tap(pets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MyPetsPage), findsOneWidget);
    expect(find.text('Administra tus mascotas registradas'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.byType(MyPetsPage), findsNothing);
  });

  testWidgets(
    'tarjeta conserva datos, imagen, edición y botón verde a 320 px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MyPetsPage(
            petsLoader: () async => [
              {
                'id': 9,
                'nombre': 'Nilo',
                'especie': 'Perro',
                'raza': 'Criollo',
                'estado': 'ACTIVA',
                'fotoPrincipal': {'url': '/api/pets/9/photos/1'},
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nilo'), findsOneWidget);
      expect(find.text('Perro · Criollo'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
      final principal = tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is NetworkImage)
          .single;
      expect(
        (principal.image as NetworkImage).url,
        endsWith('/api/pets/9/photos/1'),
      );
      expect(find.text('Agregar mascota'), findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.backgroundColor, const Color(0xFF3F9B67));
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(400, 700);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RegisterPetPage), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar mascota'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RegisterPetPage), findsOneWidget);
    },
  );

  testWidgets('estado vacío ofrece Agregar mascota sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: MyPetsPage(petsLoader: () async => [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('No tienes mascotas registradas'), findsOneWidget);
    expect(
      find.text('Agrega tu primera mascota para comenzar.'),
      findsOneWidget,
    );
    expect(find.text('Agregar mascota'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(400, 700);
    await tester.tap(find.text('Agregar mascota'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RegisterPetPage), findsOneWidget);
  });

  for (final destination in [
    (Icons.home_rounded, '/home', 'Inicio'),
    (Icons.pets_rounded, '/create-report', 'Reportar'),
    (Icons.person_rounded, '/profile', 'Perfil'),
  ]) {
    testWidgets('menú inferior de Mis Mascotas abre ${destination.$3}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MyPetsPage(petsLoader: () async => []),
          routes: {destination.$2: (_) => Scaffold(body: Text(destination.$3))},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(destination.$1).last);
      await tester.pumpAndSettle();
      expect(find.text(destination.$3), findsOneWidget);
      expect(find.byType(MyPetsPage), findsNothing);
    });
  }
}
