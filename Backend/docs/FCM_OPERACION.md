# ANIMAP-35: funcionamiento continuo

## Estado y alcance

Preparación en `codex/animap35-operacion-continua`, desde `origin/dev` (`112fc23`).
No se ha desplegado. La migración `20261102_independent_push_registration.sql` ya fue aplicada en Cloud SQL en una sesión anterior autorizada; en esta validación solo se inspeccionó el esquema con una transacción de solo lectura. Las pruebas automatizadas de esta guía usan mocks y no prueban recepción real en Android.

El Dockerfile y la plantilla de Cloud Run preparan la API Node.js. La versión unificada con HU-033 también necesita Python y los pesos de ResNet50, que aún no están incluidos en el contenedor. Su despliegue requiere una preparación posterior; no usar esta plantilla como si ya cubriera reconocimiento.

Comprobaciones de solo lectura del 1 de noviembre de 2026:

- Cloud SQL `animap-postgresql`: PostgreSQL 18.6, `southamerica-east1`, `db-g1-small`, SSD de 10 GB, máximo de 50 conexiones.
- Las dos migraciones FCM anteriores están aplicadas. La consulta de pendientes no encontró entregas FCM pendientes; había dos notificaciones con estado nulo que no se consideran eventos de este módulo.
- Node.js local: 24.19.0. Firebase Admin 14.5.0 admite los FID usados por Flutter Messaging 17.0.1. El emisor fija el proyecto `animapbd`.
- La identidad ADC local tenía `cloudmessaging.messages.create` y `serviceusage.services.use`. Esto no confirma los permisos de una futura identidad de Cloud Run.
- Atlas respondió desde esta PC. Su acceso desde Cloud Run todavía no está probado.
- FCM API está habilitada; Cloud Run, Cloud Scheduler y Secret Manager no lo están. No se ha verificado una API permanente publicada por HTTPS.
- La comprobación de solo lectura del 2 de noviembre confirma `device_push_registration.fcm_registration_id VARCHAR(255)`, `notificacion_entrega.fk_push_registration BIGINT` y las referencias históricas a sesión. Dos registros activos tienen forma de FID de 22 caracteres. La migración está aplicada; no se volvió a ejecutar.

El módulo actual avisa al propietario por **avistamientos vinculados** a una pérdida activa. No envía alertas generales de nuevas pérdidas ni coincidencias automáticas. Un avistamiento propio sigue rechazándose con HTTP 403.

## Cómo funcionará

Flutter → API Express por HTTPS → PostgreSQL y MongoDB Atlas.

El avistamiento y la intención de notificación se confirman en la misma transacción PostgreSQL. Firebase se invoca después, durante una petición autenticada de Cloud Scheduler. Un fallo de envío no revierte el avistamiento ni elimina su fotografía.

Configuración propuesta para Cloud Run:

```text
FCM_PROCESSING_MODE=scheduled
FCM_TEST_MODE=false
FCM_PUSH_ENABLED=false
NOTIFICATION_WORKER_AUDIENCE=https://URL_DEL_SERVICIO.run.app
NOTIFICATION_WORKER_SERVICE_ACCOUNT_EMAIL=CUENTA_SCHEDULER@animapbd.iam.gserviceaccount.com
```

Para desarrollo local, después de confirmar credenciales ADC y la migración ya aplicada, activar el envío general en el entorno del proceso (no en el archivo de ejemplo):

```text
FCM_TEST_MODE=false
FCM_PUSH_ENABLED=true
FCM_PROCESSING_MODE=inline
```

En este modo, la solicitud que registra el avistamiento espera a que el procesamiento y las llamadas FCM terminen. El temporizador local también recupera pendientes; no depende de trabajo en segundo plano después de responder. `Backend/.env.example` conserva `FCM_PUSH_ENABLED=false` como valor seguro inicial. No configurar IDs de propietario o reporte para el modo general.

Solo después de aprobar la validación real se cambiará `FCM_PUSH_ENABLED` a `true`. Los IDs QA no se utilizan cuando `FCM_TEST_MODE=false`.

En modo `scheduled` no se inicia el temporizador ni se despacha al crear el avistamiento. Scheduler invoca cada minuto:

```text
POST /api/internal/notifications/process
Authorization: Bearer <OIDC_DE_GOOGLE>
```

La ruta valida firma, vigencia y audiencia mediante `google-auth-library`, y exige el correo verificado de la cuenta de servicio configurada. Un JWT de AniMap no permite invocarla. Una configuración incompleta bloquea la ruta. Con push deshabilitado no consulta ni modifica pendientes.

Cada ejecución deja de reclamar nuevas entregas después de unos 45 segundos; una llamada en curso puede tardar hasta 30 segundos adicionales. Configurar 180 segundos de timeout HTTP y de plazo del trabajo. El presupuesto no es una fecha límite estricta de toda la petición: también existen consultas y cierre de resultados.

La frecuencia de un minuto implica espera de hasta aproximadamente un minuto, más arranque y procesamiento. No promete entrega inmediata. Se puede ajustar la frecuencia o la estrategia si Jira exige un plazo menor.

## Registro del dispositivo independiente de la sesión

Migración aplicada en Cloud SQL: `database/migrations/20261102_independent_push_registration.sql`.

- Crea `device_push_registration`: usuario, instalación, última sesión autenticada, FID, estado y fechas.
- Mantiene un registro por usuario/instalación y un FID único. Los registros revocados conservan la trazabilidad y liberan su FID.
- Añade `fk_push_registration` nullable a `notificacion_entrega`. Conserva su FK histórica de sesión y las huellas existentes.
- Copia únicamente asociaciones actuales de sesiones vigentes, no vencidas y con cuenta activa/verificada. No reactiva dispositivos históricos.
- Vincula las entregas existentes que coincidan con la sesión y huella. No altera su estado ni vuelve a enviar las aceptadas.
- Conserva las columnas FCM de `device_session` como espejo de compatibilidad. No modifica JWT, refresh rotation ni el plazo de inactividad de API.

El registro push permite recibir alertas después de vencer la sesión de API. Logout, revocación explícita, suspensión/eliminación de cuenta, cambio de contraseña y cambio de cuenta retiran el registro correspondiente. La cuenta y las preferencias se comprueban nuevamente antes del envío. Un resultado tardío de un FID antiguo no puede invalidar su reemplazo.

El usuario y la instalación se obtienen de la sesión autenticada. El cliente no envía un destinatario. La transferencia entre cuentas se serializa en PostgreSQL; las bajas de una sesión antigua no afectan el registro de una sesión nueva.

Al cerrar sesión Android también intenta desregistrarse en Firebase. Sin red no se puede garantizar una baja inmediata en el servidor o cancelar un mensaje ya aceptado. La app no abre avisos de otra cuenta; el backend vuelve a comprobar ownership al consultar el reporte.

La pantalla actual de sesiones solo lista sesiones de API vigentes: no es un listado de dispositivos push históricos. La retirada remota de un dispositivo cuya sesión ya expiró no tiene una interfaz específica en esta etapa. El interruptor general de preferencias y el logout desde ese dispositivo siguen disponibles.

Almacenamiento: se guarda el identificador y metadatos, no imágenes ni cuerpos completos por dispositivo. Hay un registro por usuario/instalación y una entrega por notificación/huella. El espejo temporal duplica solo el identificador en la sesión; no añade consumo a Atlas. La tabla de entregas crece con los eventos y dispositivos: acordar retención antes de un uso prolongado, sin borrar datos automáticamente.

## Recuperación y límites

Después de reiniciar o escalar a cero, la siguiente llamada de Scheduler recupera intenciones y reintentos vencidos desde PostgreSQL. No necesita que un usuario abra AniMap.

- Unicidad por avistamiento/destinatario y notificación/huella; claims atómicos con `SKIP LOCKED` permiten varias instancias.
- Máximo de tres intentos por entrega, espera exponencial con jitter y respeto de `Retry-After` para errores transitorios.
- Errores permanentes no se reintentan. Un registro inválido se retira solo si su ID, FID y versión siguen coincidiendo.
- Envíos que quedan en curso por más de 15 minutos pasan a `INDETERMINADA`. No se reenvían a ciegas: Firebase pudo aceptarlos antes del corte. Requieren revisión operativa.
- `ACEPTADA_FCM` confirma aceptación por Firebase. `recibido_en` permanece nulo: no existe todavía un acuse autenticado de Android.
- No se garantiza una única entrega física ni recepción si Android está sin red, restringe la app, niega permisos o el usuario fuerza su detención.

## Android

Se conserva Firebase Core/Messaging y sus APIs `register`, `onRegistered` y `unregister`.

- Registro al iniciar/restaurar sesión y al cambiar el FID; no bloquea autenticación si Firebase falla.
- Permiso Android solicitado con Messaging; se comprueba antes de mostrar avisos en primer plano. Se reintenta el registro al volver a la app si antes falló o no había permiso.
- Segundo plano/cierre normal: Android presenta el mensaje de notificación de FCM. No se envía desde un handler local.
- Primer plano: aviso dentro de AniMap con «Ver» y «Cerrar», sin añadir paquetes ni pantallas.
- Toque en alerta: abre el detalle propio del reporte con su historial. Si la sesión debe restaurarse, espera; una cuenta diferente no puede abrirlo. La consulta privada confirma ownership antes de navegar.
- El mensaje se deduplica por notificación dentro del proceso. No contiene tokens, fotos ni datos del reportante.

## Infraestructura propuesta — requiere autorización

1. **Cloud Run** en `southamerica-east1`: API pública HTTPS, facturación por solicitudes, mínimo 0, máximo inicial 2, 1 vCPU, 512 MiB, concurrencia 20. Pool PostgreSQL de 5 por instancia; contar también conexiones de los compañeros y revisiones durante despliegues frente al máximo de 50.
2. **Cloud SQL** mediante conexión administrada y socket `/cloudsql/animapbd:southamerica-east1:animap-postgresql`. El proxy de esta PC no participa. `DB_SSL=false` corresponde al socket administrado, no a PostgreSQL expuesto sin cifrado por Internet.
3. **Atlas** mediante Direct VPC egress y Cloud NAT con IP fija incluida en la allowlist. Revisar región, plan y acceso del usuario Mongo antes de desplegar. No abrir `0.0.0.0/0`.
4. **Identidad runtime** dedicada: Cloud SQL Client, Firebase Cloud Messaging API Admin (o rol mínimo con `cloudmessaging.messages.create`) y acceso únicamente a los secretos usados. Verificar también Service Usage según la identidad/cuota. Usar ADC de la identidad adjunta; no copiar ADC local ni claves privadas.
5. **Identidad Scheduler** distinta, sin acceso a BD/FCM; token OIDC con audiencia exacta del servicio. Mantener los permisos del agente de Scheduler para emitir ese token. La API móvil debe ser invocable públicamente; la ruta interna se protege adicionalmente en Express.
6. **Secret Manager**: contraseña PostgreSQL, secretos JWT existentes, URI Atlas, contraseña SMTP y clave Geocoding backend. Mantener valores actuales, versiones fijadas y permisos mínimos. Configuración pública de Android continúa en Flutter.
7. **Artifact Registry** para la imagen y un trabajo **Cloud Scheduler** cada minuto. Alertas por fallos del trabajo, HTTP 5xx del worker y entregas indeterminadas. Evitar tokens/cuerpos Authorization en logs.

`deploy/cloud-run.example.yaml` es una plantilla con marcadores que deben completarse. No está lista para ejecutarse sin revisión. Revisar además el modo geofence propuesto `ENFORCE` frente a la configuración que se decida conservar.

## Secuencia de despliegue

No se han ejecutado estos pasos:

1. Autorizar costos, APIs, IAM, red/IP Atlas, secretos y nombre del servicio. Verificar respaldo recuperable y permisos de DDL.
2. Mantener deshabilitados todos los emisores antiguos. Revisar pendientes existentes antes de permitir envío general.
3. Aplicar **solo** la nueva migración autorizada, con respaldo y verificación previa/posterior. Ya incluye transacción, `lock_timeout=5s` y `statement_timeout=30s`. Comprobar claves, índices, filas copiadas, permisos de tabla y secuencia para el usuario de aplicación.

   Si la migración la ejecuta un rol diferente del runtime, otorgar a este último `SELECT, INSERT, UPDATE` sobre `device_push_registration`, `USAGE, SELECT` sobre `device_push_registration_id_seq` y los permisos existentes de entregas/notificaciones. No darle DDL ni permisos de superusuario para ejecutar la API.
4. Actualizar de forma coordinada todos los backends que escriben autenticación. Una versión anterior no conoce la revocación del nuevo registro push; no mantener versiones mezcladas para funcionamiento permanente.
5. Construir la imagen usando exclusivamente `Backend/`. Docker y la subida cloud excluyen `.env`, dependencias locales, credenciales, QA, imágenes y `Reconocimiento/`.

```sh
docker build -t IMAGEN_APROBADA -f Backend/Dockerfile Backend
docker push IMAGEN_APROBADA
gcloud run services replace PLANTILLA_REVISADA --project=animapbd --region=southamerica-east1
```

6. Conocer la URL estable, fijarla como audiencia OIDC y API Android, revisar IAM público de la API y crear el trabajo autenticado. Los siguientes comandos son ejemplos; crean recursos y requieren autorización:

```sh
gcloud scheduler jobs create http animap-notifications --project=animapbd --location=southamerica-east1 --schedule="* * * * *" --time-zone=Etc/UTC --uri="https://URL_DEL_SERVICIO.run.app/api/internal/notifications/process" --http-method=POST --oidc-service-account-email="CUENTA_SCHEDULER@animapbd.iam.gserviceaccount.com" --oidc-token-audience="https://URL_DEL_SERVICIO.run.app" --attempt-deadline=180s --max-retry-attempts=2 --max-retry-duration=300s --min-backoff=60s --max-backoff=120s
flutter build apk --release --dart-define=API_BASE_URL=https://URL_DEL_SERVICIO.run.app/api
```

7. Comprobar `/api/health`, consultas autenticadas, fotos y Maps. Health confirma proceso/arranque PostgreSQL; no prueba por sí solo Atlas, Firebase o las preferencias.
8. Mantener `FCM_PUSH_ENABLED=false`: verificar que la ruta interna rechaza anónimos y JWT de AniMap, acepta solo Scheduler y no procesa entregas deshabilitadas.
9. Autorizar una prueba limitada a dos cuentas y un reporte: `FCM_TEST_MODE=true`, IDs autorizados y luego `FCM_PUSH_ENABLED=true`. Registrar un solo avistamiento ajeno. Comprobar FCM, Android y PostgreSQL.
10. Deshabilitar envío al terminar. Revisar resultados y pendientes; solo con aprobación posterior pasar a `FCM_TEST_MODE=false`, quitar los IDs QA y habilitar envío general.

Ante un problema: deshabilitar push primero y pausar Scheduler si hace falta. Se puede volver a la imagen anterior con envíos deshabilitados; conservar la tabla nueva y la FK nullable evita eliminar historial. No eliminar columnas/tablas ni restaurar Cloud SQL automáticamente.

## Costos orientativos

USD/mes, sin impuestos. Los precios regionales, el consumo y las cuotas gratuitas compartidas deben confirmarse antes de crear recursos. No constituyen una cotización de `southamerica-east1`.

| Servicio | Estimación / cómo se cobra |
|---|---|
| Cloud Run | Por CPU/RAM durante peticiones, solicitudes y tráfico. Para tres testers reservar inicialmente 0–10 USD, sujeto a medición; los arranques y cada ejecución de Scheduler también cuentan. Un mes de 30 días genera unas 43.200 llamadas del worker. |
| Cloud SQL existente | Ya factura aunque no despleguemos. `db-g1-small` tiene precio de referencia de 0,035 USD/h en Iowa (~25,55 USD/730 h), **no una tarifa confirmada de São Paulo**. Añadir 10 GB SSD, backups y tráfico según región. |
| Cloud NAT e IP | IP: 0,005 USD/h (~3,65 USD/730 h). Gateway: 0,0014 USD/h por unidad asignada hasta 32; después 0,044 USD/h. Añadir 0,045 USD/GiB procesado y egress. Validar las unidades efectivas de Direct VPC/Cloud Run; no asumir que solo se cobra la IP. |
| Scheduler | 0,10 USD por trabajo/mes; los tres primeros pueden estar cubiertos por la cuota gratuita de la cuenta de facturación. |
| Artifact Registry / builds | Referencia: 0,10 USD/GB-mes después de 0,5 GB gratuitos; añadir builds si se usa Cloud Build. Eliminar versiones antiguas requiere una política aprobada. |
| Secret Manager | Referencia: 0,06 USD por versión activa/mes y 0,03 USD por 10.000 accesos; cuota gratuita compartida de seis versiones y 10.000 accesos. |
| FCM / Atlas / tráfico | FCM no cobra por mensaje. Atlas depende del plan real, aún no confirmado. Fotos, NAT y transferencia entre regiones pueden dominar el consumo. |

No hay un total fiable hasta confirmar tarifas de São Paulo, plan Atlas y red. Comparar el total de NAT con un host pequeño de IP fija antes de aceptar el gasto; Cloud Run simplifica la identidad y Cloud SQL, pero la IP saliente tiene costo propio. Configurar presupuesto y alertas no establece un tope duro de facturación.

Fuentes oficiales: [Cloud Run y facturación](https://docs.cloud.google.com/run/docs/configuring/billing-settings), [precios Run](https://cloud.google.com/run/pricing), [Cloud SQL](https://cloud.google.com/sql/pricing), [NAT](https://cloud.google.com/nat/pricing), [Scheduler](https://cloud.google.com/scheduler/pricing), [Secret Manager](https://cloud.google.com/secret-manager/pricing), [Artifact Registry](https://cloud.google.com/artifact-registry/pricing), [FCM](https://firebase.google.com/pricing), [OIDC Scheduler](https://docs.cloud.google.com/scheduler/docs/http-target-auth), [SQL desde Run](https://docs.cloud.google.com/sql/docs/postgres/connect-run), [IP saliente estática](https://docs.cloud.google.com/run/docs/configuring/static-outbound-ip).

## Validación antes del envío general

Pruebas automatizadas usan mocks de Firebase y conexiones a bases compartidas bloqueadas. La prueba optativa `push-registration.postgres.test.js` crea y elimina su propio clúster PostgreSQL local; nunca obtiene una URL de `.env`.

La prueba real pendiente necesita dos usuarios autorizados desde redes distintas, la misma API HTTPS y un emisor controlado. Verificar: propietario correcto; otros usuarios sin alertas ajenas; reporte activo; preferencias/especie/tipo/zona; permiso Android; primer y segundo plano; toque en alerta; logout/cambio de cuenta; sesión API expirada con push vigente; reintentos y recuperación después de reiniciar/escalar a cero.

Registrar hora del avistamiento, aceptación FCM y observación visible en Android. No usar `ACEPTADA_FCM` como prueba de recepción. Conservar IDs QA y capturas saneadas fuera del repositorio. Los fallos del proveedor se prueban con mocks; no invalidar identificadores reales para simular errores. La limpieza de datos QA requiere autorización independiente.

### Resultados de esta preparación

La validación automatizada más reciente se ejecutó el 2 de noviembre de 2026. Sus resultados actualizados reemplazan cifras anteriores que aparecen en el registro histórico de abajo: Backend 307 PASS, 7 SKIP, 0 FAIL; Flutter 335 PASS; APK debug compilada. La suite completa de `flutter analyze` conserva un warning y 15 infos preexistentes en archivos no modificados por ANIMAP-35. El análisis dirigido a los archivos de esta funcionalidad no reporta problemas. La aceptación FCM de `fid` se verificó con el SDK 14.5.0 y mocks; no se comprobó recepción real en Android.

| Verificación | Resultado |
|---|---|
| Backend completo, con conexiones compartidas bloqueadas | 307 PASS, 7 SKIP, 0 FAIL (314 pruebas). Incluye envío inline esperado dentro de la solicitud y worker OIDC. |
| Compatibilidad de migración | Revisión estática contra `animap_bd.sql`: `usuario.id` y `device_session.id` son SERIAL/INTEGER, `device_id` es VARCHAR(120), FID VARCHAR(255), y la entrega usa BIGINT para la nueva referencia. No se aplicó DDL ni se conectó a Cloud SQL. La prueba PostgreSQL temporal registrada en la ronda previa no se repitió. |
| Flutter completo, API ficticia y `--no-pub` | 335 PASS, 0 FAIL. Incluye registro/permisos FCM, foreground, mensajes iniciales, logout, espera de autenticación, rechazo de otra cuenta y navegación al avistamiento exacto. |
| `dart format --output=none --set-exit-if-changed` | 0 archivos por formatear. |
| `flutter analyze --no-pub` | 0 errores; exit 1 por 1 warning preexistente en `profile_page.dart` y 15 infos preexistentes en archivos ajenos. |
| APK debug | Build exitoso con API ficticia, 163.388.631 bytes. No se instaló: no había proceso/emulador Android conectado. |
| Validación Firebase visual | No ejecutada en dispositivo físico. Los tests usan dobles; aceptación FCM y presentación Android deben comprobarse con los dos usuarios del plan. |
| Sintaxis Node / `git diff --check` | Aprobados. |
| Imagen Docker / infraestructura / envío real | No ejecutados. No se crearon recursos, no se aplicaron migraciones y no se habilitaron envíos. |

Ejecución aislada de referencia, desde `Backend/`:

```powershell
$env:MONGO_URI='mongodb://127.0.0.1:1/isolated'
npm test -- --require ./test-support/isolated.cjs
```

Para la prueba PostgreSQL local, usar un proceso distinto **sin** ese preload de bloqueo, establecer `ANIMAP_RUN_PUSH_PG_TESTS=1` y `ANIMAP_TEST_PG_BIN` al directorio `bin` de PostgreSQL instalado, y ejecutar `node --require ./test-support/env.cjs --test test/push-registration.postgres.test.js`. Esa prueba crea su propio clúster en loopback y no consulta la conexión de Cloud SQL.
