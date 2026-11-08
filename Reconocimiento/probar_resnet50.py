"""Preparar pesos oficiales y comprobar el modelo sin entrenarlo."""
import argparse
from reconocimiento import load_model, ResNetMatcher, find_sample, MODEL_ID


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--download', action='store_true', help='Descargar pesos oficiales si faltan')
    args = parser.parse_args()
    model, transform = load_model(download=args.download)
    matcher = ResNetMatcher(model, transform)
    embedding = matcher.encode(find_sample('mascota1').read_bytes())
    print(f'{MODEL_ID}: CPU, embedding de {embedding.numel()} valores, norma {embedding.norm():.6f}')
