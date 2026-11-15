# HU-034 / ANIMAP-80 — Coincidencias por fotografía

Cuando una persona publica un avistamiento con fotografía y ubicación confirmada, AniMap utiliza el ResNet50 de HU-033 para buscar posibles coincidencias con mascotas perdidas. Guarda el resultado y una intención de notificación para cada propietario elegible. Buscar por imagen, sin publicar, no genera alertas.

La similitud visual no confirma la identidad de una mascota. El umbral experimental sigue siendo configurable, con valor inicial `0.80`; no se cambia automáticamente el estado de mascotas ni reportes.

## Configuración y migración

La migración [20261108_photo_match_notifications.sql](../database/migrations/20261108_photo_match_notifications.sql) **ya fue aplicada en Cloud SQL, base `animap`, el 15/11/2026, con COMMIT y verificaciones posteriores satisfactorias**. Publicar el código no requiere volver a ejecutarla en esa base. El servidor nunca ejecuta migraciones automáticamente.

El archivo conserva su SHA-256 `0caab6c6cfb6aa80169fef6fee7c4d5612b44835d7d8a84544c0faf66f83103e`.

En otra base, revisar las dependencias antes de aplicarla: esquema base, registro FCM de sesiones, entregas de notificaciones y registro push independiente. El archivo usa una transacción, `lock_timeout=5s` y `statement_timeout=30s`. No ejecutar el script completo `animap_bd.sql` sobre una base existente: contiene operaciones destructivas.

La migración:

- Agrega `fk_reporte`, `fk_usuario`, `fk_notificacion` y `modelo` a `coincidencia_reconocimiento`.
- Permite `fk_foto_mascota` nulo y cambia su FK a `ON DELETE SET NULL`, para conservar evidencia al retirar una foto de referencia.
- Añade índices para historial y unicidad por fotografía, reporte y destinatario, y por notificación.
- Crea `reconocimiento_publicacion`, con autor, UUID de solicitud, huella, consentimiento, estado, reclamo e intentos. No duplica imágenes ni crea otra secuencia.

Los valores publicados en [.env.example](../.env.example) mantienen `PHOTO_MATCH_ENABLED=false`, `FCM_PUSH_ENABLED=false`, `RECOGNITION_QA_MODE=false` y `FCM_TEST_MODE=false`; los IDs de aislamiento están vacíos. Sin configuración explícita, el código también deja deshabilitados el análisis automático y los envíos. No se publican credenciales ni IDs de cuentas o reportes QA.

Se reutilizan Python, los pesos y las dependencias de HU-033; HU-034 no instala paquetes adicionales. Para analizar se habilita `PHOTO_MATCH_ENABLED` en el proceso autorizado. Consultar el historial de coincidencias también requiere ese interruptor; se puede analizar y consultar sin activar FCM. La entrega y el despliegue se describen en [FCM_OPERACION.md](FCM_OPERACION.md).

**Incidencia previa del instalador:** el esquema base de `dev` no define `raza.fk_especie`, `mascota.actualizado_en` ni `reporte.actualizado_en`, aunque el código existente las utiliza. Sí existen en la base compartida verificada. Una instalación completa desde cero sigue necesitando corregir el esquema común con el equipo; HU-034 no agrega esas columnas de otros módulos ni certifica ese instalador.

## Publicación, análisis y destinatarios

1. `POST /api/sightings` conserva sus validaciones de autenticación, imagen, ubicación y reporte. Vincular un reporte propio sigue devolviendo 403.
2. Con HU-034 habilitada y una foto, exige UUID de publicación y confirmación explícita de la ubicación. La foto se guarda una sola vez en MongoDB; el avistamiento y su trabajo de análisis se confirman juntos en PostgreSQL.
3. ResNet50 se ejecuta después del COMMIT. Un fallo posterior no elimina la foto ni revierte el avistamiento confirmado.
4. Se revalidan reporte ACTIVO, mascota PERDIDA, propietario, preferencias, especie, tipo de evento y radio. «Solo mi zona» usa el punto original de pérdida como centro; si faltan coordenadas, no se ignora el filtro.
5. Se selecciona el mejor resultado por propietario, hasta tres propietarios, en orden de similitud e ID de reporte. No se avisa al autor sobre sus propias mascotas.
6. Se reutilizan `notificacion`, `notificacion_entrega` y los dispositivos push elegibles de ANIMAP-35. La alerta vinculada y la coincidencia del mismo evento/destinatario comparten una intención; puede conservarse además una alerta vinculada para otro propietario.

La clave UUID se conserva al reintentar: los mismos datos reutilizan la publicación; cambiar datos con la misma clave devuelve 409. Distintas observaciones legítimas usan otra clave. El porcentaje lo calcula el backend con ResNet50, nunca Flutter.

## Contrato HTTP añadido

Estas consultas requieren `Authorization: Bearer <accessToken>`. El destinatario se obtiene de la sesión. No se acepta un propietario elegido por el cliente.

| Método y ruta | Entrada | Respuesta |
|---|---|---|
| `GET /api/recognition/matches` | `before` opcional: entero positivo | `{ok:true,data:[coincidencia]}`, hasta 50 por página, ID descendente. Usar el último ID como siguiente cursor. |
| `GET /api/recognition/matches/:id` | ID positivo | `{ok:true,data:coincidencia}` del propietario autenticado. |
| `GET /api/recognition/matches/:id/image` | ID positivo | Bytes de imagen con `Content-Type`; `Cache-Control: private, no-store`. |

Las respuestas JSON también usan `private, no-store`. Errores: 400 para IDs o cursor inválidos; 401/403 de autenticación; 404 para un recurso inexistente, ajeno o no disponible; 503 si HU-034 está deshabilitada.

Una coincidencia contiene `id`, `reportId`, `sightingId`, `similarity`, `threshold`, `model`, `observedAt`, `createdAt`, `notificationState`, `photoUrl`, `location={lat,lng,method,address}`, `reporter={label,phone?}` y `pet={name}`. La API expresa similitud y umbral entre 0 y 1; PostgreSQL guarda porcentajes. Las fechas del avistamiento y del análisis se devuelven separadas en ISO UTC.

`POST /api/sightings` reutiliza multipart y añade `solicitudId` UUID, `ubicacionConfirmada` y `compartirContacto`. Para una foto analizada se requieren UUID y `ubicacionConfirmada=true`; el contacto es opcional y desactivado por defecto. Se conservan formatos JPG/JPEG/PNG/WEBP, firma válida y máximo 5 MiB. Sin foto se conserva el flujo anterior. Flutter normaliza extensión y MIME a la firma real cuando Android redimensiona una imagen.

## Privacidad y contenido de la notificación

El aviso FCM muestra «Posible coincidencia con tu mascota perdida» y la similitud redondeada. El payload de datos incluye tipo e IDs de coincidencia, notificación, avistamiento, reporte y destinatario. **No incluye fotografía, miniatura pública, coordenadas exactas ni contacto.**

Al tocarlo, AniMap comprueba la cuenta y consulta el detalle autenticado, donde aparecen la fotografía, ubicación, fechas y similitud. Si falta una sesión válida, conserva el destino hasta autenticar al usuario correcto. Los datos privados se limpian al cambiar de cuenta y se descartan respuestas tardías de otra sesión.

El nombre y teléfono del reportante solo se muestran con consentimiento afirmativo. Sin consentimiento aparece «Reportante», sin teléfono. El correo no se comparte. La fotografía de la coincidencia exige propiedad del evento; las fotografías públicas legítimas de reportes y avistamientos conservan sus reglas anteriores.

El historial privado permite abrir el detalle y «Ver mi reporte». El historial general registra la notificación, pero su navegación existente abre contenido del mapa/avistamiento; no abre directamente el detalle privado de coincidencia. No se modificó el módulo del compañero para unificar esos destinos. Abrir desde el push no marca automáticamente la notificación como leída.

## Recuperación y fallos

El trabajo pendiente sobrevive a un reinicio. En modo `inline`, el procesador se ejecuta al iniciar y cada 30 segundos; en `scheduled`, la ruta OIDC procesa primero análisis y luego entregas. Cloud Run sin CPU fuera de solicitudes necesita el disparador autenticado descrito en FCM_OPERACION, no solo el temporizador.

Un reclamo abandonado se recupera tras 15 minutos con un identificador nuevo, que impide confirmar resultados de un proceso anterior. Hay máximo tres análisis y espera exponencial; un tercer reclamo interrumpido se finaliza sin otro análisis. Al agotarse, queda el motivo y se conserva la alerta vinculada de ANIMAP-35 cuando corresponde.

FCM registra resultados por dispositivo con huellas, sin tokens en logs. Los errores transitorios permiten hasta tres intentos, con espera exponencial y respeto de `Retry-After`; los permanentes no se repiten. Una asociación invalidada no debe afectar otra nueva. Una respuesta incierta queda `INDETERMINADA` y no se reenvía automáticamente.

`ACEPTADA_FCM` significa aceptación por Firebase, no recepción física en Android. Las restricciones e idempotencia reducen duplicados; no garantizan una única entrega física. El recuperador de propietarios solo trata `AVISTAMIENTO_VINCULADO` y `COINCIDENCIA_FOTOGRAFICA`, sin reclamar entregas administrativas o comunitarias.

## Aislamiento para pruebas

`RECOGNITION_QA_MODE=true` exige `FCM_TEST_MODE=true`, `FCM_TEST_OWNER_ID`, `FCM_TEST_REPORT_ID` y `RECOGNITION_QA_REPORTER_ID`, positivos y con usuarios distintos. Estos valores se configuran solo en el proceso de prueba, no como constantes. Si falta configuración, falla antes de consultar candidatos o ejecutar el modelo.

El filtro se aplica antes de consultar fotos, al leerlas y al reclamar/finalizar/recuperar trabajos. Solo admite el propietario/reporte y el reportante configurados; no busca alternativas globales si el reporte deja de estar disponible. Utilizar una cuenta reportante dedicada, porque sus publicaciones independientes forman parte de ese alcance.

Con `FCM_PUSH_ENABLED=false` pueden generarse coincidencias e intenciones pendientes. Revisar y autorizar su procesamiento antes de habilitar envíos, incluso cuando se desactive posteriormente el modo QA. Los emisores administrativos y comunitarios tienen interruptores independientes y deben coordinarse con el equipo.

## Aceptación y pruebas

Revisión final del 15/11/2026, con datos sintéticos autorizados en Cloud SQL y Atlas, ResNet50 real y Android independiente. Los manifiestos, capturas, cuentas e IDs QA permanecen fuera del repositorio.

| Criterio | Resultado y salvedad |
|---|---|
| Push al propietario | Una notificación real aceptada por Firebase y recibida visiblemente en Android. Tocar el aviso abrió la coincidencia autenticada. |
| Fotografía, ubicación y similitud en el aviso | No hay cumplimiento literal completo: el aviso mostró 99 %; la foto y la ubicación se consultaron en el detalle, con 98,9 % visible y 98,89 % almacenado. La alternativa privada estaba prevista en la especificación. |
| Acceso al reporte/contacto | Detalle y enlace al reporte disponibles. Contacto afirmativo probado con mocks, Flutter y PostgreSQL temporal; Android compartido se probó con consentimiento desactivado. |
| Historial protegido | Evento persistido y disponible para su propietario. Otra cuenta no accedió al detalle/imagen; solicitudes anónimas recibieron 401. |
| Registro de errores y reintentos | Verificados con pruebas aisladas, incluidos fallos transitorios/permanentes, reinicios y aceptación incierta. No se provocaron fallos reales del proveedor. |

La prueba real usó un procesador de un solo uso restringido al evento y dispositivo QA, con un prefijo de prueba añadido en memoria. No se activaron envíos generales. Se comprobó aceptación y recepción por separado. Al cierre no quedaron notificaciones, entregas ni análisis QA pendientes; esta observación corresponde al instante revisado, no a futuras publicaciones.

| Verificación final | Resultado |
|---|---|
| Backend completo con conexiones compartidas bloqueadas | 404 aprobadas, 11 omitidas optativas, 0 fallos. |
| PostgreSQL temporal; modelo, MongoDB y FCM simulados | 11 aprobadas, 0 fallos; consentimiento afirmativo, concurrencia, privacidad y recuperación. |
| Flutter completo con servicios simulados | 362 aprobadas, 0 fallos; incluye regresión JPEG/PNG. |
| Python unitario | 8 aprobadas, 0 fallos. ResNet50 real se verificó por separado en la prueba Android. |
| `flutter analyze --no-pub` | 0 errores, 2 warnings y 15 infos previos; salida 1 por esos avisos, no un análisis limpio. |
| `git diff --check` | Sin errores de whitespace. |

**Minimapa:** el encuadre anterior al volver a elegir un punto ya existe en la versión base de `dev`. Afecta la vista previa del formulario: `initialCameraPosition` no vuelve a centrar una vista reutilizada. Las coordenadas guardadas, geofence y detalle fueron correctos. No se corrige dentro de HU-034 sin coordinación; requiere una corrección visual y prueba específica de cámara nativa.

Para repetir pruebas aisladas, `test-support/isolated.cjs` bloquea conexiones PostgreSQL/MongoDB reales. Las pruebas PostgreSQL optativas crean su propio clúster local y lo detienen al terminar; no deben apuntarse a Cloud SQL. Las suites Flutter usan `--no-pub` y `--dart-define=API_BASE_URL=http://example.invalid/api`. No incluir evidencia QA, APK ni archivos de configuración real al publicar.
