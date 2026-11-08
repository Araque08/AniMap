"""Evaluate only explicitly verified identity labels; never infer labels from filenames."""
import argparse
import json
from pathlib import Path
from reconocimiento import ResNetMatcher


def evaluate(items, similarity, threshold=0.8):
    counts = {'truePositive': 0, 'falsePositive': 0, 'trueNegative': 0, 'falseNegative': 0}
    for index, a in enumerate(items):
        for b in items[index + 1:]:
            actual = a['identity'] == b['identity']
            predicted = similarity(a, b) >= threshold
            counts[('true' if predicted == actual else 'false') + ('Positive' if predicted else 'Negative')] += 1
    positives = counts['truePositive'] + counts['falseNegative']
    negatives = counts['trueNegative'] + counts['falsePositive']
    return {**counts, 'threshold': threshold, 'sufficientClasses': positives > 0 and negatives > 0,
            'precision': counts['truePositive'] / (counts['truePositive'] + counts['falsePositive'])
            if counts['truePositive'] + counts['falsePositive'] else None,
            'recall': counts['truePositive'] / positives if positives else None}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--threshold', type=float, default=0.8)
    args = parser.parse_args()
    data = json.loads(args.manifest.read_text(encoding='utf-8'))
    items = data.get('images', [])
    if data.get('identitiesVerified') is not True or len(items) < 2 or any(
            not isinstance(item.get('identity'), str) or not item['identity'].strip() for item in items):
        parser.error('Se requieren identidades verificadas y al menos dos fotografías etiquetadas.')
    if not 0 <= args.threshold <= 1: parser.error('El umbral debe estar entre 0 y 1.')
    matcher = ResNetMatcher()
    def embedding(item):
        return matcher.encode((args.manifest.parent / item['path']).read_bytes())
    print(json.dumps(evaluate(items, lambda a, b: matcher.similarity(embedding(a), embedding(b)), args.threshold)))
