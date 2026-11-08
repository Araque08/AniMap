"""Comparaci?n manual de Sebasti?n usando el extractor compartido."""
import argparse
from pathlib import Path
from reconocimiento import ResNetMatcher, find_sample
_matcher = ResNetMatcher()


def comparar_imagenes(ruta1, ruta2):
    return _matcher.similarity(_matcher.encode(Path(ruta1).read_bytes()),
                               _matcher.encode(Path(ruta2).read_bytes()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('imagen1', nargs='?', type=Path)
    parser.add_argument('imagen2', nargs='?', type=Path)
    args = parser.parse_args()
    result = comparar_imagenes(args.imagen1 or find_sample('mascota1'),
                              args.imagen2 or find_sample('mascota2'))
    print(f'Similitud visual: {result:.4f} ({result * 100:.2f} %). No es probabilidad de identidad.')
