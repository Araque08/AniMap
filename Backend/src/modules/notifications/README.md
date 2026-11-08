# Notificaciones de avistamientos — ANIMAP-35

Este módulo avisa al dueño cuando otra persona registra un avistamiento vinculado a su reporte activo. No envía alertas generales de pérdidas ni coincidencias automáticas.

## Configuración

- Node.js 22 o posterior. Se usa `firebase-admin` 14.5.0, importando solo `app` y `messaging`.
- Proyecto de destino fijo: `animapbd`.
- Credenciales mediante Application Default Credentials (ADC), fuera del repositorio. No se utiliza `google-services.json` como credencial del servidor.
- `FCM_PUSH_ENABLED=false` por defecto. No se inicializa Firebase, consulta la cola ni registra intenciones mientras esté deshabilitado. Tampoco se recuperan retroactivamente avistamientos creados en ese modo.
- Antes de habilitarlo hay que revisar y aplicar por separado `Backend/database/migrations/20261101_sighting_push_notifications.sql`, comprobar los permisos SQL y autorizar el primer envío real.

La existencia de un archivo ADC no demuestra que tenga permisos de envío. Antes de la prueba real hay que verificar que la identidad disponga de `cloudmessaging.messages.create` en `animapbd` y que la API FCM HTTP v1 esté habilitada. No se crean identidades, claves privadas ni permisos desde este módulo.

## Aislamiento de una prueba QA

El modo de prueba está apagado por defecto. Se configura solo en el entorno del backend:

```dotenv
FCM_PUSH_ENABLED=false
FCM_TEST_MODE=true
FCM_TEST_OWNER_ID=<ID del propietario QA autorizado>
FCM_TEST_REPORT_ID=<ID del reporte QA autorizado>
```

Sustituir el marcador por un ID entero positivo real antes de la prueba. El código no fija ningún usuario ni reporte. Con `FCM_TEST_MODE=true`, deben coincidir **ambos** IDs para registrar una intención, recuperar pendientes o reclamar y enviar una entrega. Los eventos ajenos no generan filas, ni siquiera como omitidos, y no se acumulan para enviarlos después.

Si falta un ID, no es un entero positivo compatible con PostgreSQL, o el modo tiene un valor distinto de `true`/`false`, se bloquea toda actividad del procesador. Las preferencias y las comprobaciones de sesión/FID siguen aplicándose. Las notificaciones ajenas que ya existían se conservan intactas y quedan fuera de esta prueba.

Estos valores se leen al iniciar Node.js. Todos los procesos que procesen notificaciones contra la misma base deben usar el mismo aislamiento; este modo no controla un backend independiente configurado para enviar sin restricciones.

Para preparar la prueba, configurar los tres valores QA y reiniciar el backend **manteniendo `FCM_PUSH_ENABLED=false`**. El modo QA por sí solo no permite ningún envío. Solo tras la autorización específica del envío real se podrá activar el interruptor general y reiniciar.

Al terminar, poner primero `FCM_PUSH_ENABLED=false` y reiniciar. Para retirar el aislamiento, usar `FCM_TEST_MODE=false`; los IDs se ignoran en modo normal. No volver a activar envíos normales sin revisar los pendientes anteriores. Un mensaje ya aceptado por Firebase no puede retirarse cambiando estas variables. Esta implementación no modifica el `.env` existente.

## Flujo

1. `createSighting()` guarda avistamiento, ubicación, foto e intención de notificación en la misma transacción PostgreSQL. No llama a Firebase dentro de ella.
2. Tras el COMMIT y la liberación de la conexión se despierta el procesador para ese avistamiento. En modo `inline`, la petición espera el intento FCM y su persistencia antes de responder. En modo `scheduled`, la petición no envía; Cloud Scheduler procesa la cola con OIDC.
3. El procesador consulta el dueño a través de `avistamiento → reporte → usuario`, y vuelve a comprobar reporte, preferencias y sesiones antes del envío.
4. Firebase recibe el campo `fid`, compatible con `register()` / `onRegistered` de Flutter Messaging 17. No se cambia la integración Android.
5. El resultado se registra por dispositivo. En modo `inline`, la respuesta espera a que termine el intento, no a la recepción visual en Android. En modo `scheduled`, Firebase se procesa fuera de la petición de creación.

Con el módulo habilitado, si no puede persistirse la intención, falla la transacción aún no confirmada. Así no se confirma un avistamiento cuya intención se haya perdido. Un fallo de Firebase ocurre siempre después del COMMIT y no afecta esa creación.

## Destinatarios y preferencias

Solo se consideran el propietario del reporte, una cuenta disponible y verificada, y sesiones vigentes, no vencidas y con FID. El autor no recibe una alerta sobre su propio reporte. Los FID repetidos se deduplican.

Se respetan el interruptor general y los filtros de especie y tipo de evento. Para **Solo mi zona**, el centro provisional aprobado es el punto original de pérdida, **no la ubicación actual ni el domicilio del usuario**. Se calcula la distancia al avistamiento en kilómetros. Si faltan coordenadas o el radio es inválido, se registra un motivo `OMITIDA_ZONA_*`; no se ignora el filtro.

## Persistencia

`notificacion` conserva un evento por avistamiento y destinatario. Su nuevo `fk_avistamiento` es opcional, por lo que las filas anteriores permanecen válidas.

`notificacion_entrega` conserva una fila por evento y huella SHA-256 del FID. Guarda la sesión, intentos, próximo intento, error saneado y resultado de FCM. El identificador completo sigue únicamente en `device_session`; no se copia a la tabla de entregas ni se registra en logs.

| Estado de entrega | Significado |
|---|---|
| PENDIENTE | Todavía no se intentó enviar. |
| EN_PROCESO | Un proceso adquirió esta entrega. |
| REINTENTO | Fallo transitorio; espera hasta `proximo_intento_en`. |
| ACEPTADA_FCM | FCM aceptó el mensaje; no demuestra recepción en Android. |
| FALLIDA_PERMANENTE | Error definitivo o tres intentos agotados. |
| OMITIDA | El reporte, las preferencias o la sesión ya no permiten enviarla. |
| INDETERMINADA | No se puede saber con seguridad si FCM aceptó la solicitud. |

`recibido_en` queda NULL: todavía no hay confirmación autenticada desde Android. `aceptado_en` mide aceptación del proveedor, no entrega efectiva.

## Reinicios y reintentos

En modo `inline`, el servidor consulta al iniciar y cada 30 segundos como respaldo local; cada nueva petición espera además el procesamiento dirigido de su avistamiento. Para Cloud Run con CPU suspendida entre solicitudes, usar `scheduled`: el worker OIDC consulta pendientes y reintentos por petición de Scheduler. Las intenciones confirmadas antes de un reinicio permanecen en PostgreSQL. También reconcilia resúmenes incompletos: una entrega pendiente se recupera aunque el estado general haya quedado desactualizado. Los errores transitorios usan hasta tres intentos totales, con espera exponencial de al menos 60 y 120 segundos, variación aleatoria y respeto de `Retry-After` cuando el SDK lo proporciona. Las entregas ya aceptadas no se vuelven a reclamar.

Las restricciones únicas, el claim atómico con `SKIP LOCKED` y la etiqueta Android por notificación reducen duplicados entre procesos y dispositivos. No garantizan una única entrega física.

Una operación abandonada en `EN_PROCESO` durante 15 minutos pasa a `INDETERMINADA`. No se reenvía automáticamente: pudo haber sido aceptada antes del reinicio. Lo mismo ocurre con un timeout sin resultado confirmado. Estos casos requieren revisión, sin editar estados a ciegas.

La sesión y la huella se revalidan inmediatamente antes del envío. Si FCM informa que el FID ya no existe, se elimina la asociación solo si coinciden sesión, propietario, FID original y fecha de asociación. Una respuesta tardía no debe borrar una asociación nueva. No es posible hacer atómica una llamada externa con una revocación que suceda después de la comprobación; los mensajes aceptados tampoco se pueden retirar desde PostgreSQL.

## Pruebas

```bash
node --require ./test-support/isolated.cjs --test test/notifications.push.test.js test/notifications.repository.test.js test/firebase.sender.test.js test/sightings.push-commit.test.js
```

Se simulan PostgreSQL, MongoDB y el transporte Firebase. Una prueba usa el SDK instalado con credenciales falsas que fallan antes de cualquier solicitud externa, para comprobar que acepta `fid`. El preload impide conexiones reales a las bases y deshabilita los envíos predeterminados.

## Prueba real pendiente

Después de autorizar la migración y la configuración ADC, se necesitarán dos cuentas autorizadas: dueño con sesión/FID vigente y colaborador distinto. Con autorización de escritura se crearán datos temporales, se registrará un avistamiento vinculado y se comprobarán por separado la aceptación FCM y la recepción Android, inicialmente con la app en segundo plano.

No se ha implementado confirmación de recepción, presentación en primer plano ni navegación al detalle al tocar la notificación. Esas validaciones y cualquier cambio Flutter se revisarán por separado. La limpieza de datos temporales deberá comprobar referencias e imágenes sin afectar información previa.
