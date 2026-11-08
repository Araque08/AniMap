import io
import unittest
from PIL import Image
import torch

from reconocimiento import ResNetMatcher, RecognitionError, find_sample
from evaluar_umbral import evaluate


def photo(color='red'):
    result = io.BytesIO()
    Image.new('RGB', (64, 48), color).save(result, format='PNG')
    return result.getvalue()


class FakeModel:
    def __init__(self): self.calls = 0
    def __call__(self, tensor):
        self.calls += 1
        return tensor.mean(dim=(2, 3))


class RecognitionTests(unittest.TestCase):
    def setUp(self):
        self.model = FakeModel()
        self.matcher = ResNetMatcher(model=self.model,
            transform=lambda image: torch.tensor(image.resize((1, 1)).getpixel((0, 0)))
                .float().reshape(3, 1, 1), cache_size=2)

    def test_embedding_normalized_and_cached_by_actual_content(self):
        a = self.matcher.encode(photo())
        b = self.matcher.encode(photo())
        self.assertTrue(torch.equal(a, b))
        self.assertAlmostEqual(float(a.norm()), 1.0, places=6)
        self.assertEqual(self.model.calls, 1)
        self.matcher.encode(photo('blue'))
        self.assertEqual(self.model.calls, 2)

    def test_cosine_not_identity_probability(self):
        a, b = self.matcher.encode(photo('red')), self.matcher.encode(photo('blue'))
        self.assertAlmostEqual(self.matcher.similarity(a, a), 1.0, places=6)
        self.assertAlmostEqual(self.matcher.similarity(a, b), 0.0, places=6)

    def test_damaged_unsupported_and_oversized_images(self):
        for content in [b'not-an-image', b'x' * (5 * 1024 * 1024 + 1)]:
            with self.assertRaises(RecognitionError): self.matcher.encode(content)
        gif = io.BytesIO(); Image.new('RGB', (8, 8)).save(gif, format='GIF')
        with self.assertRaises(RecognitionError): self.matcher.encode(gif.getvalue())

    def test_cache_is_bounded(self):
        for color in ['red', 'blue', 'green', 'red']: self.matcher.encode(photo(color))
        self.assertEqual(self.model.calls, 4)

    def test_camera_dimensions_accepted_and_pixel_bombs_rejected(self):
        for size, valid in [((4624, 3468), True), ((5001, 5000), False)]:
            data = io.BytesIO()
            Image.new('1', size, 1).save(data, format='PNG')
            if valid: self.assertTrue(torch.isfinite(self.matcher.encode(data.getvalue())).all())
            else:
                with self.assertRaises(RecognitionError): self.matcher.encode(data.getvalue())

    def test_zero_or_nonfinite_embeddings_rejected(self):
        for value in [0.0, float('nan')]:
            matcher = ResNetMatcher(model=lambda _: torch.tensor([[value, value]]),
                transform=lambda _: torch.ones(3, 1, 1))
            with self.assertRaises(RecognitionError): matcher.encode(photo())

    def test_existing_jpeg_samples_resolve_without_renaming(self):
        self.assertEqual(find_sample('mascota1').suffix, '.jpeg')
        self.assertEqual(find_sample('mascota2').suffix, '.jpeg')

    def test_labeled_evaluation_counts_errors_without_inventing_accuracy(self):
        items = [{'identity': 'A', 'id': 1}, {'identity': 'A', 'id': 2}, {'identity': 'B', 'id': 3}]
        scores = {(1, 2): 0.7, (1, 3): 0.9, (2, 3): 0.2}
        result = evaluate(items, lambda a, b: scores[a['id'], b['id']])
        self.assertEqual([result[k] for k in ['truePositive', 'falsePositive', 'trueNegative', 'falseNegative']], [0, 1, 1, 1])
        self.assertTrue(result['sufficientClasses'])
        self.assertFalse(evaluate(items[:1], lambda a, b: 1)['sufficientClasses'])


if __name__ == '__main__': unittest.main()
