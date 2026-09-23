import 'dart:async';

import 'package:animap/features/pet/presentation/pages/my_pets_page.dart';
import 'package:animap/features/pet/presentation/pages/pet_profile_page.dart';
import 'package:animap/features/user/presentation/pages/profile_options_pages.dart';
import 'package:animap/features/user/presentation/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> userProfile({String? photo}) => {
  'nombre': 'Felipe',
  'email': 'felipe@example.invalid',
  'telefono': '300 000 0000',
  'foto_url': photo,
};

PetProfile petProfile(int photoCount, {String estado = 'ACTIVA'}) {
  return PetProfile(
    id: 77,
    fkUsuario: 9,
    fkEspecie: 1,
    fkRaza: 2,
    nombre: 'Nilo',
    especie: 'Perro',
    raza: 'Criollo',
    color: 'Café',
    sexo: 'MACHO',
    estado: estado,
    observaciones: 'Temporal',
    edadAprox: 2,
    unidadEdad: 'ANIOS',
    photos: List.generate(
      photoCount,
      (index) => PetPhoto(
        id: index + 1,
        storageRef: 'photo-$index',
        urlPreview: '/api/pets/images/photo-$index',
        esPrincipal: index == 7,
      ),
    ),
  );
}

Future<void> pumpPersonalInfo(
  WidgetTester tester, {
  PersonalProfileUpdater? updater,
  VoidCallback? onUpdated,
  ValueChanged<Map<String, dynamic>>? onProfileUpdated,
  String? photo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PersonalInfoPage(
        profile: userProfile(photo: photo),
        onUpdated: onUpdated ?? () {},
        onProfileUpdated: onProfileUpdated,
        profileUpdater: updater,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Información Personal', () {
    testWidgets('muestra la misma foto autenticada del perfil', (tester) async {
      const path = '/api/profile/photo/507f1f77bcf86cd799439011';
      await pumpPersonalInfo(tester, photo: path);

      final avatar = tester.widget<CircleAvatar>(
        find.byKey(const ValueKey('personal-info-avatar')),
      );
      expect(avatar.backgroundImage, isA<NetworkImage>());
      expect((avatar.backgroundImage! as NetworkImage).url, endsWith(path));
    });

    testWidgets('guardar sin cambios y whitespace equivalente hacen 0 PATCH', (
      tester,
    ) async {
      var patches = 0;
      await pumpPersonalInfo(
        tester,
        updater: ({required nombre, required telefono}) async {
          patches++;
          return userProfile();
        },
      );

      await tester.ensureVisible(find.text('Guardar información'));
      await tester.ensureVisible(find.text('Guardar información'));
      await tester.tap(find.text('Guardar información'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(patches, 0);
      expect(find.text('No realizaste cambios.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), '  Felipe  ');
      await tester.tap(find.text('Guardar información'));
      await tester.pump();
      expect(patches, 0);
    });

    testWidgets('un cambio real actualiza cabecera, teléfono y conserva foto', (
      tester,
    ) async {
      const photoPath = '/api/profile/photo/507f1f77bcf86cd799439011';
      var patches = 0;
      var updates = 0;
      Map<String, dynamic>? propagatedProfile;
      await pumpPersonalInfo(
        tester,
        photo: photoPath,
        onUpdated: () => updates++,
        onProfileUpdated: (profile) => propagatedProfile = profile,
        updater: ({required nombre, required telefono}) async {
          patches++;
          return {
            ...userProfile(photo: photoPath),
            'nombre': nombre,
            'telefono': telefono,
          };
        },
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'Felipe AniMap');
      await tester.enterText(find.byType(TextFormField).at(2), '311 222 3344');
      await tester.ensureVisible(find.text('Guardar información'));
      await tester.tap(find.text('Guardar información'));
      await tester.pumpAndSettle();
      expect(patches, 1);
      expect(updates, 1);
      expect(propagatedProfile?['nombre'], 'Felipe AniMap');
      expect(propagatedProfile?['telefono'], '311 222 3344');
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('personal-info-header-name')),
            )
            .data,
        'Felipe AniMap',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(2))
            .controller
            ?.text,
        '311 222 3344',
      );
      final avatar = tester.widget<CircleAvatar>(
        find.byKey(const ValueKey('personal-info-avatar')),
      );
      expect(
        (avatar.backgroundImage! as NetworkImage).url,
        endsWith(photoPath),
      );

      await tester.ensureVisible(find.text('Guardar información'));
      await tester.tap(find.text('Guardar información'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(patches, 1);
      expect(find.text('No realizaste cambios.'), findsOneWidget);
    });

    testWidgets('ProfilePage muestra el nombre actualizado al volver', (
      tester,
    ) async {
      var patches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePage(
            profileLoader: () async => userProfile(),
            personalProfileUpdater:
                ({required nombre, required telefono}) async {
                  patches++;
                  return {
                    ...userProfile(),
                    'nombre': nombre,
                    'telefono': telefono,
                  };
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Información Personal'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Nombre Nuevo');
      await tester.ensureVisible(find.text('Guardar información'));
      await tester.tap(find.text('Guardar información'));
      await tester.pumpAndSettle();
      expect(patches, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('profile-header-name')))
            .data,
        'Nombre Nuevo',
      );
      expect(patches, 1);
    });

    testWidgets('es responsive a 320 px sin overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpPersonalInfo(tester);
      await tester.scrollUntilVisible(
        find.text('Guardar información'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Felipe'), findsWidgets);
      expect(find.text('felipe@example.invalid'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('estado de mascotas', () {
    testWidgets('ACTIVA es normal, PERDIDA se destaca y legacy es coherente', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MyPetsPage(
            petsLoader: () async => [
              {
                'id': 1,
                'nombre': 'Activa',
                'especie': 'Perro',
                'raza': 'Criollo',
                'estado': 'ACTIVA',
              },
              {
                'id': 2,
                'nombre': 'Perdida',
                'especie': 'Gato',
                'raza': 'Muy larga',
                'estado': 'PERDIDA',
              },
              {
                'id': 3,
                'nombre': 'Legacy',
                'especie': 'Perro',
                'raza': 'Criollo',
                'estado': 'ENCONTRADA',
              },
              {
                'id': 4,
                'nombre': 'Eliminada',
                'especie': 'Perro',
                'raza': 'Criollo',
                'estado': 'INACTIVA',
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Activa'), findsWidgets);
      expect(find.text('Perdida'), findsWidgets);
      expect(find.byKey(const ValueKey('pet-status-PERDIDA')), findsOneWidget);
      expect(find.text('Encontrada'), findsNothing);
      expect(find.text('Eliminada'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('galería y eliminación de mascota', () {
    testWidgets('+X es exacto para 15, 16 y 20 fotos', (tester) async {
      for (final count in [15, 16, 20]) {
        await tester.pumpWidget(
          MaterialApp(
            home: PetProfilePage(
              key: ValueKey('pet-$count'),
              mascotaId: 77,
              profileLoader: (_) async => petProfile(count),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('+${count - 3}'), findsOneWidget);
      }
    });

    testWidgets(
      '+X abre todas las fotos con principal primero y visor grande',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PetProfilePage(
              mascotaId: 77,
              profileLoader: (_) async => petProfile(15),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('pet-gallery-more')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pet-gallery-more')));
        await tester.pumpAndSettle();

        expect(find.text('Todas las fotos (15)'), findsOneWidget);
        final firstImage = tester.widget<Image>(
          find.descendant(
            of: find.byKey(const ValueKey('report-gallery-photo-0')),
            matching: find.byType(Image),
          ),
        );
        final firstProvider = firstImage.image;
        final firstNetwork = firstProvider is ResizeImage
            ? firstProvider.imageProvider as NetworkImage
            : firstProvider as NetworkImage;
        expect(firstNetwork.url, endsWith('photo-7'));
        expect(find.byIcon(Icons.delete), findsNothing);

        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('report-gallery-photo-14')),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('report-gallery-photo-14')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('report-gallery-photo-14')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('report-photo-viewer')),
          findsOneWidget,
        );
        expect(find.text('15 de 15'), findsOneWidget);
      },
    );

    testWidgets(
      'confirmación usa nombre dinámico, cancelar no llama y bloquea doble',
      (tester) async {
        var deleteCalls = 0;
        final completion = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            initialRoute: '/pet',
            routes: {
              '/': (_) => const Scaffold(body: Text('Anterior')),
              '/pet': (_) => PetProfilePage(
                mascotaId: 77,
                profileLoader: (_) async => petProfile(15),
                deleteAction: (_) {
                  deleteCalls++;
                  return completion.future;
                },
              ),
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Eliminar mascota'));
        await tester.pumpAndSettle();
        expect(find.text('¿Eliminar mascota?'), findsOneWidget);
        expect(
          find.textContaining('Estás a punto de eliminar a Nilo'),
          findsOneWidget,
        );
        final highlighted = tester
            .widgetList<Text>(find.byType(Text))
            .any(
              (text) =>
                  text.textSpan is TextSpan &&
                  ((text.textSpan as TextSpan).children
                          ?.whereType<TextSpan>()
                          .any(
                            (span) =>
                                span.text == 'Nilo' &&
                                span.style?.fontWeight == FontWeight.w900,
                          ) ??
                      false),
            );
        expect(highlighted, isTrue);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(deleteCalls, 0);

        await tester.tap(find.byTooltip('Eliminar mascota'));
        await tester.pumpAndSettle();
        final deleteButton = find.byKey(const ValueKey('confirm-delete-pet'));
        await tester.tap(deleteButton);
        await tester.tap(deleteButton);
        expect(deleteCalls, 1);
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        completion.complete();
        await tester.pumpAndSettle();
        expect(deleteCalls, 1);
        expect(find.text('Anterior'), findsOneWidget);
      },
    );
  });
}
