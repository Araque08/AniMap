
import torch
from torchvision import models
from torch import nn

# Cargar ResNet50 con sus pesos preentrenados
print("Cargando ResNet50 preentrenada...")

modelo = models.resnet50(
    weights=models.ResNet50_Weights.DEFAULT
)

# Quitar la última capa de clasificación
# para obtener embeddings de 2048 valores
modelo.fc = nn.Identity()

# Activar modo de evaluación
modelo.eval()

print("Modelo cargado correctamente.")

# Crear una imagen de prueba artificial
imagen_prueba = torch.zeros(1, 3, 224, 224)

# Generar un embedding sin entrenar el modelo
with torch.no_grad():
    embedding = modelo(imagen_prueba)

print("Embedding generado correctamente.")
print("Dimensiones del embedding:", embedding.shape)
print("Cantidad de características:", embedding.shape[1])
