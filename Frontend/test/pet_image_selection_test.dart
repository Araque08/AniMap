import 'dart:typed_data';

import 'package:animap/features/pet/data/pet_image_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  group('validación de fotos de mascota', () {
    test('selección mixta conserva válidas y rechaza cada inválida', () async {
      final valid = _png('valida.png', marker: 1);
      final invalidFormat = XFile.fromData(
        Uint8List.fromList([0x47, 0x49, 0x46]),
        path: 'archivo.gif',
      );
      final tooLarge = _jpeg('grande.jpg', length: maxPetImageBytes + 1);

      final result = await validatePetImageSelection(
        selected: [valid, invalidFormat, tooLarge],
        alreadyAdded: const [],
      );

      expect(result.accepted, [valid]);
      expect(result.rejected, hasLength(2));
      expect(
        result.rejected.map((item) => item.reason),
        containsAll([
          PetImageRejectionReason.unsupportedFormat,
          PetImageRejectionReason.tooLarge,
        ]),
      );
      expect(result.rejectionMessage, contains('2 fotos rechazadas'));
      expect(result.rejectionMessage, contains('formato no permitido'));
      expect(result.rejectionMessage, contains('máximo de 5 MB'));
    });

    test('rechaza una imagen que supera 5 MB', () async {
      final result = await validatePetImageSelection(
        selected: [_jpeg('grande.jpeg', length: maxPetImageBytes + 1)],
        alreadyAdded: const [],
      );

      expect(result.accepted, isEmpty);
      expect(result.rejected.single.reason, PetImageRejectionReason.tooLarge);
    });

    test('rechaza extensión no permitida', () async {
      final result = await validatePetImageSelection(
        selected: [
          XFile.fromData(
            Uint8List.fromList([0x47, 0x49, 0x46]),
            path: 'mascota.gif',
          ),
        ],
        alreadyAdded: const [],
      );

      expect(result.accepted, isEmpty);
      expect(
        result.rejected.single.reason,
        PetImageRejectionReason.unsupportedFormat,
      );
    });

    test('detecta duplicados por contenido aunque cambie el nombre', () async {
      final original = _png('original.png', marker: 7);
      final sameContent = _png('copia_con_otro_nombre.png', marker: 7);
      final differentContentWithSameName = _png('original.png', marker: 8);

      final result = await validatePetImageSelection(
        selected: [sameContent, differentContentWithSameName],
        alreadyAdded: [original],
      );

      expect(result.accepted, [differentContentWithSameName]);
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.reason, PetImageRejectionReason.duplicate);
      expect(result.rejectionMessage, contains('Esta foto ya fue agregada'));
    });

    test('acepta JPG, PNG y WEBP válidos de hasta 5 MB', () async {
      final result = await validatePetImageSelection(
        selected: [
          _jpeg('uno.jpg'),
          _png('dos.PNG', marker: 2),
          _webp('tres.webp'),
          _jpeg('limite.jpeg', length: maxPetImageBytes),
        ],
        alreadyAdded: const [],
      );

      expect(result.accepted, hasLength(4));
      expect(result.rejected, isEmpty);
    });

    test(
      'acepta el registro normal con 15 imágenes válidas distintas',
      () async {
        final images = List.generate(
          15,
          (index) => _png('mascota_$index.png', marker: index),
        );

        final result = await validatePetImageSelection(
          selected: images,
          alreadyAdded: const [],
        );

        expect(result.accepted, hasLength(15));
        expect(result.rejected, isEmpty);
      },
    );
  });

  group('orden de foto principal', () {
    test('mueve la foto elegida a la posición 1', () {
      final images = ['primera', 'segunda', 'principal'];

      moveImageToFirst(images, 2);

      expect(images, ['principal', 'primera', 'segunda']);
    });

    test('conserva la principal en posición 1 al recargar', () {
      final images = [
        {'id': 'a', 'esPrincipal': false},
        {'id': 'b', 'esPrincipal': true},
        {'id': 'c', 'esPrincipal': false},
      ];

      final ordered = principalImageFirst(
        images,
        (image) => image['esPrincipal'] == true,
      );

      expect(ordered.first['id'], 'b');
      expect(
        ordered.where((image) => image['esPrincipal'] == true),
        hasLength(1),
      );
    });

    test('reorganiza secundarias sin mover la principal', () {
      final images = ['principal', 'a', 'b', 'c'];

      moveSecondaryImage(images, 3, 1);
      moveSecondaryImage(images, 0, 2);

      expect(images, ['principal', 'c', 'a', 'b']);
    });

    test('solo permite eliminar cuando quedan más de 15 fotos', () {
      expect(canDeletePetImage(15), isFalse);
      expect(canDeletePetImage(16), isTrue);
    });
  });
}

XFile _png(String name, {required int marker}) {
  return XFile.fromData(
    Uint8List.fromList([
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      marker,
    ]),
    path: name,
  );
}

XFile _jpeg(String name, {int length = 4}) {
  final bytes = Uint8List(length);
  bytes[0] = 0xff;
  bytes[1] = 0xd8;
  bytes[2] = 0xff;
  bytes[3] = 1;
  return XFile.fromData(bytes, path: name);
}

XFile _webp(String name) {
  return XFile.fromData(
    Uint8List.fromList([
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x45,
      0x42,
      0x50,
    ]),
    path: name,
  );
}
