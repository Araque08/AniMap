"""CPU embeddings for HU-033. No database, network server or training here."""
import hashlib
import io
from pathlib import Path
from collections import OrderedDict
import warnings
import torch
from torchvision import models
from PIL import Image, ImageOps

MODEL_ID = 'resnet50-imagenet1k-v2'
MAX_BYTES = 5 * 1024 * 1024
Image.MAX_IMAGE_PIXELS = 25_000_000


class RecognitionError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def find_sample(name, folder=None):
    folder = folder or Path(__file__).parent / 'imagenes_prueba'
    found = [p for p in folder.iterdir() if p.stem == name
             and p.suffix.lower() in {'.jpg', '.jpeg', '.png', '.webp'}]
    if len(found) != 1: raise RecognitionError('SAMPLE_NOT_FOUND_OR_AMBIGUOUS')
    return found[0]


def load_model(download=False):
    weights = models.ResNet50_Weights.IMAGENET1K_V2
    filename = weights.url.rsplit('/', 1)[-1]
    checkpoint = Path(torch.hub.get_dir()) / 'checkpoints' / filename
    if download: weights.get_state_dict(progress=False, check_hash=True)
    if not checkpoint.is_file(): raise RecognitionError('MODEL_NOT_CONFIGURED')
    expected = filename.rsplit('-', 1)[-1].split('.')[0]
    with checkpoint.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if not digest.startswith(expected): raise RecognitionError('MODEL_CHECKSUM_INVALID')
    model = models.resnet50(weights=None)
    model.load_state_dict(torch.load(checkpoint, map_location='cpu', weights_only=True))
    model.fc = torch.nn.Identity()
    model.eval().to('cpu')
    torch.set_num_threads(2)
    return model, weights.transforms()


class ResNetMatcher:
    def __init__(self, model=None, transform=None, cache_size=1024):
        self.model, self.transform = model, transform
        self.cache_size = max(1, cache_size)
        self.cache = OrderedDict()

    def encode(self, content):
        if not content or len(content) > MAX_BYTES: raise RecognitionError('INVALID_IMAGE')
        key = hashlib.sha256(content).hexdigest()
        if key in self.cache:
            self.cache.move_to_end(key)
            return self.cache[key]
        try:
            with warnings.catch_warnings():
                warnings.simplefilter('error', Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(content)) as original:
                    if original.format not in {'JPEG', 'PNG', 'WEBP'}:
                        raise RecognitionError('INVALID_IMAGE')
                    if original.width * original.height > Image.MAX_IMAGE_PIXELS:
                        raise RecognitionError('INVALID_IMAGE')
                    original.load()
                    image = ImageOps.exif_transpose(original).convert('RGB')
        except RecognitionError: raise
        except Exception: raise RecognitionError('INVALID_IMAGE') from None
        try:
            if self.model is None: self.model, self.transform = load_model()
            with torch.inference_mode():
                embedding = self.model(self.transform(image).unsqueeze(0)).flatten().float().cpu()
                norm = torch.linalg.vector_norm(embedding)
                if not torch.isfinite(embedding).all() or not torch.isfinite(norm) or norm <= 0:
                    raise RecognitionError('MODEL_INVALID_EMBEDDING')
                embedding = embedding / norm
        except RecognitionError: raise
        except Exception: raise RecognitionError('MODEL_UNAVAILABLE') from None
        self.cache[key] = embedding
        if len(self.cache) > self.cache_size: self.cache.popitem(last=False)
        return embedding

    @staticmethod
    def similarity(a, b):
        value = float(torch.dot(a, b))
        if not torch.isfinite(torch.tensor(value)): raise RecognitionError('MODEL_INVALID_EMBEDDING')
        return max(-1.0, min(1.0, value))
