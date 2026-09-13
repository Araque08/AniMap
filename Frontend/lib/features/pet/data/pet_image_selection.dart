import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

const int maxPetImageBytes = 5 * 1024 * 1024;
const int maxPetImagesPerSelection = 30;

enum PetImageRejectionReason {
  unsupportedFormat,
  tooLarge,
  empty,
  duplicate,
  selectionLimit,
  unreadable,
}

class PetImageRejection {
  final XFile image;
  final PetImageRejectionReason reason;

  const PetImageRejection({required this.image, required this.reason});
}

class PetImageSelectionResult {
  final List<XFile> accepted;
  final List<PetImageRejection> rejected;

  const PetImageSelectionResult({
    required this.accepted,
    required this.rejected,
  });

  String? get rejectionMessage {
    if (rejected.isEmpty) return null;

    final counts = <PetImageRejectionReason, int>{};
    for (final rejection in rejected) {
      counts.update(rejection.reason, (value) => value + 1, ifAbsent: () => 1);
    }

    final details = <String>[];
    void addDetail(PetImageRejectionReason reason, String description) {
      final count = counts[reason];
      if (count != null) details.add('$count $description');
    }

    addDetail(
      PetImageRejectionReason.unsupportedFormat,
      'por formato no permitido (usa JPG/JPEG, PNG o WEBP)',
    );
    addDetail(
      PetImageRejectionReason.tooLarge,
      'por superar el máximo de 5 MB',
    );
    addDetail(PetImageRejectionReason.empty, 'por estar vacía');
    final duplicateCount = counts[PetImageRejectionReason.duplicate];
    if (duplicateCount == 1) {
      details.add('1 duplicada (Esta foto ya fue agregada)');
    } else if (duplicateCount != null) {
      details.add(
        '$duplicateCount duplicadas (Estas fotos ya fueron agregadas)',
      );
    }
    addDetail(
      PetImageRejectionReason.selectionLimit,
      'por superar el máximo de 30 fotos por operación',
    );
    addDetail(
      PetImageRejectionReason.unreadable,
      'porque no se pudo leer el archivo',
    );

    final count = rejected.length;
    final label = count == 1 ? 'foto rechazada' : 'fotos rechazadas';
    return '$count $label: ${details.join('; ')}.';
  }
}

class _KnownImage {
  final XFile image;
  final int length;
  final String fingerprint;

  const _KnownImage({
    required this.image,
    required this.length,
    required this.fingerprint,
  });
}

Future<PetImageSelectionResult> validatePetImageSelection({
  required List<XFile> selected,
  required List<XFile> alreadyAdded,
  int maxBytes = maxPetImageBytes,
  int maxImages = maxPetImagesPerSelection,
}) async {
  final accepted = <XFile>[];
  final rejected = <PetImageRejection>[];
  final knownImages = <_KnownImage>[];

  for (final image in alreadyAdded) {
    try {
      final bytes = await image.readAsBytes();
      knownImages.add(
        _KnownImage(
          image: image,
          length: bytes.length,
          fingerprint: _contentFingerprint(bytes),
        ),
      );
    } catch (_) {
      // Una foto previamente aceptada no debe bloquear una selección nueva.
    }
  }

  for (final image in selected) {
    final extension = _extensionOf(image.name);
    if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
      rejected.add(
        PetImageRejection(
          image: image,
          reason: PetImageRejectionReason.unsupportedFormat,
        ),
      );
      continue;
    }

    try {
      final length = await image.length();
      if (length <= 0) {
        rejected.add(
          PetImageRejection(
            image: image,
            reason: PetImageRejectionReason.empty,
          ),
        );
        continue;
      }
      if (length > maxBytes) {
        rejected.add(
          PetImageRejection(
            image: image,
            reason: PetImageRejectionReason.tooLarge,
          ),
        );
        continue;
      }

      final bytes = await image.readAsBytes();
      if (!_hasValidImageSignature(bytes, extension)) {
        rejected.add(
          PetImageRejection(
            image: image,
            reason: PetImageRejectionReason.unsupportedFormat,
          ),
        );
        continue;
      }

      final fingerprint = _contentFingerprint(bytes);
      var duplicate = false;
      for (final known in knownImages) {
        if (known.length != bytes.length || known.fingerprint != fingerprint) {
          continue;
        }

        final knownBytes = await known.image.readAsBytes();
        if (_sameBytes(bytes, knownBytes)) {
          duplicate = true;
          break;
        }
      }

      if (duplicate) {
        rejected.add(
          PetImageRejection(
            image: image,
            reason: PetImageRejectionReason.duplicate,
          ),
        );
        continue;
      }

      if (knownImages.length >= maxImages) {
        rejected.add(
          PetImageRejection(
            image: image,
            reason: PetImageRejectionReason.selectionLimit,
          ),
        );
        continue;
      }

      accepted.add(image);
      knownImages.add(
        _KnownImage(image: image, length: length, fingerprint: fingerprint),
      );
    } catch (_) {
      rejected.add(
        PetImageRejection(
          image: image,
          reason: PetImageRejectionReason.unreadable,
        ),
      );
    }
  }

  return PetImageSelectionResult(accepted: accepted, rejected: rejected);
}

void moveImageToFirst<T>(List<T> images, int index) {
  if (index <= 0 || index >= images.length) return;
  final selected = images.removeAt(index);
  images.insert(0, selected);
}

void moveSecondaryImage<T>(List<T> images, int from, int to) {
  if (from <= 0 || from >= images.length || to <= 0 || images.length < 2) {
    return;
  }
  final target = to.clamp(1, images.length - 1).toInt();
  if (from == target) return;
  final image = images.removeAt(from);
  images.insert(target, image);
}

bool canDeletePetImage(int currentCount, {int minimum = 15}) {
  return currentCount > minimum;
}

List<T> principalImageFirst<T>(
  Iterable<T> images,
  bool Function(T image) isPrincipal,
) {
  return [
    ...images.where(isPrincipal),
    ...images.where((image) => !isPrincipal(image)),
  ];
}

String _extensionOf(String name) {
  final separator = name.lastIndexOf('.');
  return separator < 0 ? '' : name.substring(separator + 1).toLowerCase();
}

bool _hasValidImageSignature(Uint8List bytes, String extension) {
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
    case 'png':
      const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
      return bytes.length >= signature.length &&
          _sameBytes(bytes.sublist(0, signature.length), signature);
    case 'webp':
      return bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    default:
      return false;
  }
}

String _contentFingerprint(Uint8List bytes) {
  var first = 0x811c9dc5;
  var second = 0x1505;
  for (final byte in bytes) {
    first = ((first ^ byte) * 0x01000193) & 0xffffffff;
    second = (((second << 5) + second) ^ byte) & 0xffffffff;
  }
  return '${bytes.length}:$first:$second';
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
