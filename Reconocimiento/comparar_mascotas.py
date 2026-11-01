
import torch
from torchvision import models
from torch import nn
from PIL import Image
from pathlib import Path

# ============================================
# 1. CARGAR RESNET50 PREENTRENADA
# ============================================

print("Cargando ResNet50...")

pesos = models.ResNet50_Weights.DEFAULT

modelo = models.resnet50(weights=pesos)

# Eliminar la capa final de clasificación
modelo.fc = nn.Identity()

modelo.eval()

# Preparación oficial de imágenes para ResNet50
transformacion = pesos.transforms()

print("Modelo cargado correctamente.")


# ============================================
# 2. GENERAR EMBEDDINGS
# ============================================

def generar_embedding(ruta_imagen):

    imagen = Image.open(ruta_imagen).convert("RGB")

    imagen_procesada = transformacion(imagen)

    imagen_procesada = imagen_procesada.unsqueeze(0)

    with torch.no_grad():
        embedding = modelo(imagen_procesada)

    return embedding


# ============================================
# 3. COMPARAR EMBEDDINGS
# ============================================

def comparar_imagenes(ruta1, ruta2):

    embedding1 = generar_embedding(ruta1)
    embedding2 = generar_embedding(ruta2)

    similitud = torch.nn.functional.cosine_similarity(
        embedding1,
        embedding2,
        dim=1
    )

    return similitud.item()


# ============================================
# 4. EJECUTAR PRUEBA
# ============================================

carpeta = Path(__file__).resolve().parent / "imagenes_prueba"

imagen1 = carpeta / "mascota1.jpg"
imagen2 = carpeta / "mascota2.jpg"

if not imagen1.exists() or not imagen2.exists():
    print("ERROR: No se encontraron las imágenes de prueba.")
    print("Verifica que existan mascota1.jpg y mascota2.jpg.")
else:

    print("\nComparando fotografías de mascotas...")

    resultado = comparar_imagenes(imagen1, imagen2)

    print("\n========== RESULTADO ==========")
    print(f"Similitud del coseno: {resultado:.4f}")
    print(f"Similitud visual (escala porcentual): {resultado * 100:.2f}%")
    print("================================")

    print("\nComparación finalizada correctamente.")
