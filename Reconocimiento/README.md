# HU-033 / ANIMAP-79 — Buscar mascota por fotografía

Desde «Reportar y Buscar», el usuario puede elegir cámara o galería, revisar la foto e iniciar una búsqueda. Los resultados muestran posibles coincidencias y permiten abrir el detalle existente del reporte. No crean reportes, avistamientos ni notificaciones.

## Preparación local

Se validó en Windows con Python 3.14.5, PyTorch 2.15.0 CPU, Torchvision 0.29.2 y Node.js 24. Las dependencias Python se mantienen en un entorno virtual de este directorio; no se instalan en Android.

Desde la raíz del proyecto:

```powershell
py -m venv Reconocimiento/.venv
& .\Reconocimiento\.venv\Scripts\python.exe -m pip install -r Reconocimiento/requirements.txt
& .\Reconocimiento\.venv\Scripts\python.exe Reconocimiento/probar_resnet50.py --download
```

El último comando descarga, si faltan, los pesos oficiales `IMAGENET1K_V2` de ResNet50 (~98 MiB), verifica su hash y prueba el extractor. Los pesos permanecen en la caché local de PyTorch, fuera de Git. El backend no descarga pesos durante las solicitudes: si faltan o Python falla, responde con un error controlado.

El worktree necesita la configuración habitual de PostgreSQL, MongoDB y JWT. No copia automáticamente el `.env` de otro worktree. Conserva los valores existentes y consulta `Backend/.env.example` para los nombres de las variables.

Configuración nueva, opcional:

```text
RECOGNITION_SIMILARITY_THRESHOLD=0.80
RECOGNITION_PYTHON=
```

Si se omite `RECOGNITION_PYTHON`, Express usa `Reconocimiento/.venv/Scripts/python.exe` en Windows o `.venv/bin/python` en Linux. Un umbral vacío, inválido o fuera de 0–1 bloquea la búsqueda, sin afectar los demás módulos. El cliente no puede cambiarlo por parámetros.

Configura `Backend/.env` a partir de `.env.example`, sin versionar sus valores. Desde `Backend/`:

```powershell
$env:PORT='3000'
$env:FCM_PUSH_ENABLED='false'
node src/server.js
```

Esto requiere que el proxy y las bases configuradas estén disponibles. Si el puerto está ocupado, elige otro mediante `PORT` y utiliza el mismo en Flutter. No es necesario iniciar un servidor Python separado ni aplicar migraciones para reconocimiento.

Desde `Frontend/`, con un emulador conectado:

```powershell
flutter run -d ID_DEL_EMULADOR --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

Un Android físico debe usar una dirección de esta PC accesible desde su red, en lugar de `10.0.2.2`. El modo release mantiene la exigencia HTTPS existente. No se cambió la configuración de Maps, Firebase ni la autenticación.

## Cómo se compara

Express inicia un único proceso Python privado bajo demanda y lo conserva para las siguientes búsquedas. Se comunica por stdin/stdout con JSON; Python no abre puertos ni recibe credenciales de las bases.

ResNet50 se carga una vez por proceso, en CPU y modo evaluación. Se elimina su clasificador, se usan las transformaciones oficiales de sus pesos y se obtienen vectores normalizados de 2048 valores. La comparación es el coseno entre vectores. No se entrena un modelo nuevo.

La caché en memoria conserva hasta 1024 embeddings (~8 MiB de vectores), identificados por SHA-256 del contenido. Una foto que cambia se recalcula; dos solicitudes sobre los mismos bytes reutilizan el embedding. La fotografía de consulta no se guarda en disco, PostgreSQL ni Atlas. El proceso conserva embeddings de forma temporal y los pierde al reiniciar.

PostgreSQL selecciona **todas** las referencias `foto_mascota` de reportes `ACTIVO` con mascota `PERDIDA`, comprobando la relación propietario/mascota/reporte. Atlas entrega únicamente documentos `ImagenMascota` con ID y propietario correspondientes y `estado=ACTIVA`. Las fotos ausentes o inválidas se omiten y cuentan en la respuesta.

Se conservan como máximo cinco reportes, ordenados por similitud descendente, con la mejor foto de cada uno. Antes de responder se consultan de nuevo las relaciones activas y los bytes de las fotos elegidas. Si desaparece la mejor foto, se intenta la siguiente del mismo reporte. Las URLs usan el endpoint público existente del mapa, que vuelve a comprobar la visibilidad. No se exponen datos del propietario ni fotografías privadas sin reporte activo.

Solo se procesa una búsqueda a la vez por backend. Otra recibe 429. Hay límite adicional de seis solicitudes por usuario/minuto, timeout de búsqueda de 120 s y timeout por intercambio Python de 35 s. Al cancelar o vencer el tiempo se detiene ese worker; la siguiente solicitud puede reiniciarlo. Una búsqueda muy grande puede agotar el plazo y debe reintentarse; la caché ayuda en búsquedas repetidas, pero esta versión no es un índice vectorial.

Se aceptan JPEG, PNG y WEBP, hasta 5 MiB y 25 millones de píxeles. Esto incluye las fotos de cámara de 12,6 y 16 megapíxeles verificadas en los registros actuales. Se revisan MIME/firma y se decodifica realmente la imagen en Python. La UI permite reintentar conservando la selección; cerrar la búsqueda cancela su cliente HTTP.

## API

`POST /api/recognition/search` — Bearer obligatorio, usuario autenticado con cuenta y sesión válidas.

Enviar `multipart/form-data` con un único archivo **foto**, sin campos adicionales. No admite rutas locales, URLs, IDs de destinatario ni umbrales enviados por el cliente.

Respuesta 200:

```json
{
  "ok": true,
  "model": "resnet50-imagenet1k-v2",
  "threshold": 0.8,
  "searchedImages": 30,
  "skippedImages": 0,
  "matches": [{
    "reportId": 123,
    "pet": {"id": 456, "nombre": "Ejemplo", "especie": "Perro", "raza": null, "color": "Café"},
    "photo": {"id": "000000000000000000000001", "url": "/api/map/images/000000000000000000000001"},
    "similarity": 0.85
  }]
}
```

Los datos anteriores son ficticios. `matches=[]` indica que no hubo fotos actuales que superaran el umbral. `searchedImages` cuenta las fotos comparadas, no mascotas; `skippedImages` cuenta fotos no disponibles/decodificables. Un fallo del modelo o de las bases no se presenta como ausencia de coincidencias.

| HTTP | Código / causa |
|---|---|
| 400 | `INVALID_RECOGNITION_IMAGE`: falta archivo, formato/decodificación inválidos o multipart incorrecto. |
| 401/403 | Reglas de sesión y cuenta existentes de AniMap. |
| 413 | `RECOGNITION_IMAGE_TOO_LARGE`: supera 5 MiB. |
| 429 | `RECOGNITION_BUSY` o `RECOGNITION_RATE_LIMIT`. |
| 503 | `RECOGNITION_UNAVAILABLE`: configuración, Python, modelo o dependencia no disponible. |
| 504 | `RECOGNITION_TIMEOUT`: venció el procesamiento. |

Los errores no incluyen rutas del servidor, fotos, tokens ni mensajes crudos de los proveedores.

## Similitud y umbral del 80 %

La interfaz muestra **Similitud visual**, no probabilidad de identidad. ResNet50 está preentrenada en ImageNet; no es un modelo especializado en identificar individuos de mascotas. Fondo, postura, iluminación y animales parecidos pueden influir mucho.

Los archivos disponibles no incluyen etiquetas verificadas de identidad. Por eso **no se ha validado que 0.80 separe correctamente mascotas iguales y distintas**, ni se afirma precisión, tasa de aciertos o cumplimiento cuantitativo de ese criterio.

En la prueba técnica real, consultar el mismo archivo produjo coseno `0.99999994`; el otro archivo de prueba produjo `0.84502065`. Sin conocer su identidad, ese segundo resultado no permite clasificarlo como acierto o falso positivo. La comparación del mismo archivo solo confirma el funcionamiento del recorrido.

Para evaluar con etiquetas proporcionadas por el equipo, completar un manifiesto local basado en `identidades.example.json` con `identitiesVerified=true` e imágenes `{ "path": "imagenes_prueba/archivo.jpeg", "identity": "etiqueta-verificada" }`. Incluir varias fotos diferentes por mascota y varias mascotas. El script rechaza etiquetas no verificadas:

```powershell
& .\.venv\Scripts\python.exe evaluar_umbral.py MANIFIESTO_LOCAL.json --threshold 0.80
```

Calcula pares positivos/negativos, falsos positivos/negativos, precisión y recall; indica si faltan clases para evaluarlos. No se deben inventar identidades por el nombre del archivo. Mantener fotografías personales y manifiestos reales fuera de Git. El umbral inicial queda sujeto a esa evaluación.

## Pruebas y revisión manual

Desde `Reconocimiento/`:

```powershell
& .\.venv\Scripts\python.exe -m unittest -v test_reconocimiento
& .\.venv\Scripts\python.exe comparar_mascotas.py
```

`comparar_mascotas.py` resuelve `.jpg` y `.jpeg` sin renombrar las imágenes de Sebastián y también acepta dos rutas como argumentos.

Desde `Backend/`, la suite aislada bloquea PostgreSQL/MongoDB reales:

```powershell
$env:MONGO_URI='mongodb://127.0.0.1:1/isolated'
npm test -- --require ./test-support/isolated.cjs
$env:ANIMAP_RUN_RECOGNITION_REAL='1'
node --require ./test-support/env.cjs --require ./test-support/isolated.cjs --test test/recognition.python.test.js
```

La segunda prueba usa HTTP, JWT, IPC, Python y ResNet50 reales, con candidatos de prueba y almacenamiento simulado. No usa cuentas ni registros compartidos. La prueba optativa `recognition.postgres.test.js` crea su propio clúster PostgreSQL local si se define `ANIMAP_RUN_RECOGNITION_PG=1` y `ANIMAP_TEST_PG_BIN`; no lee la conexión de Cloud SQL y limpia solo su clúster temporal.

Desde `Frontend/`:

```powershell
flutter test --no-pub --dart-define=API_BASE_URL=http://example.invalid/api test/image_recognition_test.dart test/report_navigation_pet_photos_test.dart test/map_filters_test.dart
flutter analyze --no-pub
```

En Android: iniciar sesión normalmente, abrir Huella → Reportar y Buscar → botón de cámara; probar cámara y galería, preview, búsqueda, resultados y apertura del reporte. Probar cancelar, otra imagen, sin resultados y error de conexión. Verificar que los filtros/listados originales siguen funcionando. Una prueba con bases compartidas no debe crear ni modificar mascotas, reportes o avistamientos; cualquier autenticación automatizada necesita la autorización correspondiente.

### Verificación realizada — 7 de noviembre de 2026

| Prueba | Resultado |
|---|---|
| Python | 8 pruebas aprobadas: embeddings, coseno, caché, imágenes inválidas, límites, dimensiones reales de cámara, extensiones y evaluación de etiquetas. |
| Backend aislado | 308 PASS, 8 SKIP, 0 FAIL; incluye 12 casos de reconocimiento con mocks. Conexiones reales bloqueadas. |
| HTTP + JWT + Python + ResNet50 reales | 1 PASS, candidatos aislados. El proceso Python se reutilizó entre solicitudes. |
| Consulta SQL en PostgreSQL temporal | 1 PASS; estados, propietario y todas las fotos. El clúster propio se eliminó al terminar. |
| Flutter | Suite completa: 331 PASS. Nueve pruebas específicas de HU-033; incluyen el detalle real existente, un reporte que se cierra antes de abrirlo y la cancelación durante la carga del archivo. |
| Análisis y compilación | Sin errores nuevos; 16 diagnósticos anteriores de `dev`. APK debug compilada para una API local. |
| Cloud SQL + Atlas + ResNet50, solo lectura | 60 referencias de 3 reportes activos, 59 fotos comparadas y 1 documento ausente. PostgreSQL confirmó `transaction_read_only=on`. |
| Control positivo con una foto existente | Se devolvió su reporte correcto con similitud 1.0. Confirma la integración, no precisión sobre fotos distintas. |
| Android con dispositivo real/emulador | Pendiente: no había dispositivos conectados. Cámara/galería y navegación se probaron con widgets simulados. |

Los dos casos optativos de integración se ejecutaron por separado de la suite aislada; las otras seis pruebas omitidas corresponden a integraciones externas preexistentes. Una foto de muestra del repositorio no obtuvo coincidencias con las fotos actuales al umbral 0.80. No se modificó la referencia cuyo documento está ausente ni se intentó repararla automáticamente.

En esa verificación, con `FCM_PUSH_ENABLED=false`, `/api/health` respondió 200 y la búsqueda sin Bearer respondió 401. No se ejecutó autenticación contra la base compartida. La preparación de contenedores para incluir Python y los pesos corresponde a una etapa posterior; el Dockerfile de ANIMAP-35 solo prepara Node.js y no permite desplegar todavía el reconocimiento.

El límite inicial de 12 MP se corrigió a 25 MP tras comprobar que excluía 22 fotografías válidas de cámara. La repetición comparó las 59 imágenes disponibles. Las evidencias agregadas no contienen nombres de personas, credenciales ni bytes de las fotografías y se conservaron fuera del repositorio.

### Archivos del bloque

- Backend: `src/modules/recognition/recognition.routes.js`, `recognition.service.js`, `recognition.repository.js`, `recognition.worker.js`; montaje en `src/routes/index.js` y variables documentadas en `.env.example`.
- Tests Backend: `test/recognition.test.js`, `recognition.worker.test.js`, `recognition.python.test.js`, `recognition.postgres.test.js`.
- Flutter: `lib/features/report/data/image_recognition_service.dart`, `presentation/widgets/image_search_sheet.dart`, `presentation/pages/report_search_page.dart` y `test/image_recognition_test.dart`.
- Python: `reconocimiento.py`, `worker.py`, `evaluar_umbral.py`, `test_reconocimiento.py`, `requirements.txt`, `identidades.example.json`, `.gitignore` y este README. Se adaptaron `comparar_mascotas.py` y `probar_resnet50.py`; se conservaron todas las imágenes originales.
