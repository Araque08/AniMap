# AniMap — API REST

**66 operaciones**, agrupadas por módulo. Las rutas incluyen `/api`, sin `/v1`. Configuración y arquitectura: [README](../README.md).

## Uso general

| Acceso | Qué necesita |
|---|---|
| Público | No requiere token; no necesariamente revisa el header Authorization. |
| Sesión | `Authorization: Bearer <ACCESS_TOKEN>`. Comprueba token, sesión, cuenta y rol en PostgreSQL. |
| Administrador | Sesión válida y rol ADMINISTRADOR vigente. |
| Opcional | El mapa admite consultas sin token; si se envía, lo valida sin revisar toda la sesión. |
| Refresh token | `refreshToken` en el cuerpo, sin exigir access token. |

El propietario se obtiene de `req.auth.userId`; enviar otro `userId` no permite acceder a recursos ajenos.

Enviar JSON para datos y multipart/form-data con boundary para archivos. JSON/urlencoded: hasta 10 KB. Auth y PATCH de perfil/preferencias exigen JSON.

`?` indica opcional; `trim`, quitar espacios al inicio/final. IDs: enteros positivos; fotos: ObjectId/referencia MongoDB. Éxito: **200**, salvo **201** indicado. Las respuestas JSON incluyen `ok`, excepto geofence/check. No hay paginación.

Imágenes: bytes con Content-Type. Resolver URLs relativas contra el origen del backend; las privadas requieren Bearer. Fechas: Reportes ISO -05:00; Avistamientos Z; otras, formato del driver PostgreSQL. Mapa/TODAY usan Bogotá; 7D/30D, intervalos UTC con límite inferior incluido.

### Errores comunes

Formato habitual: `{ok:false,message,code?}`; validación compartida: `{ok:false,message:"Datos inválidos",errors:[{field,message}]}`. JSON malformado/excesivo y rutas inexistentes pueden tener otro formato.

| HTTP | Significado |
|---|---|
| 400 | Parámetros, cuerpo o archivo inválidos. |
| 401 / 403 | Token/sesión inválida, vencida o revocada / cuenta, rol o permiso no válido. |
| 404 / 409 | Recurso inexistente o ajeno / duplicado o conflicto de estado. |
| 415 / 429 | Formato no admitido / demasiadas solicitudes. |
| 422 | Ubicación fuera de zona en ENFORCE. |
| 500 / 502 / 503 | Fallo interno / respuesta inválida del proveedor / servicio no disponible. |

Las tablas solo añaden errores específicos.

### Ubicación

En Reportes van dentro de `ubicacion`; en Avistamientos, como campos multipart:

| Campo | Regla |
|---|---|
| metodo | GPS, MAPA o DIRECCION. |
| lat, lng | Convertibles a número; -90..90 y -180..180. Siempre obligatorios. |
| precisionM | Opcional/null, 0..100000. |
| direccion | Opcional/null, trim hasta 255; obligatoria en DIRECCION. |
| placeId | Opcional/null, trim hasta 150; obligatorio en DIRECCION. |

DIRECCION guarda una dirección geocodificada. En GPS/MAPA, `direccion` es referencia adicional: no reemplaza las coordenadas ni se geocodifica.

## Autenticación y sesiones (10)

[Rutas y validaciones](../src/modules/auth/auth.routes.js).

| Método | Ruta | Función | Acceso | Recibe (JSON) | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| POST | /api/auth/register | Registrar cuenta | Público | Registro | 201: data=usuario + verificationEmailSent | 409 correo existente |
| POST | /api/auth/login | Iniciar sesión | Público | email, password, deviceId? | data={user,accessToken,refreshToken} | 401 credenciales; 403 cuenta/rol |
| POST | /api/auth/refresh | Renovar tokens | Refresh token | refreshToken | data={accessToken,refreshToken,role} | 401/403 |
| POST | /api/auth/logout | Revocar sesión | Refresh token | refreshToken | data={revoked:true} | 401 si ya no es válida |
| GET | /api/auth/sessions | Listar sesiones propias | Sesión | — | data=[sesión] | Comunes |
| POST | /api/auth/sessions/:id/revoke | Revocar otra sesión propia | Sesión | :id; sin cuerpo requerido | data={revoked:true} | 404 SESSION_NOT_FOUND; 409 CURRENT_SESSION |
| POST | /api/auth/verify-account | Verificar cuenta | Público | email, code | data=usuario verificado | 400 código/ya verificada; 403; 404 |
| POST | /api/auth/resend-verification-code | Reenviar código | Público | email | data={email,sent} | 400 ya verificada; 403; 404 |
| POST | /api/auth/forgot-password | Solicitar recuperación | Público | email | data={email,sent} | 403; 404 |
| POST | /api/auth/reset-password | Cambiar contraseña con código | Público | email, code, newPassword, confirmPassword | data={email,passwordReset:true} | 400 código/contraseñas; 403; 404 |

Todas incluyen `message`, excepto el listado de sesiones.

| Datos | Validación |
|---|---|
| Registro | nombre trim 3–120; email válido trim/minúsculas hasta 150; telefono trim 10–20, admite números, +, guiones, espacios y paréntesis; password; aceptaTyC=true. |
| Password registro/reset | Mínimo 8, mayúscula, minúscula, número y carácter no alfanumérico; sin máximo en ese schema. Reset exige confirmación igual. |
| Login | Mismo email; password 1–100; deviceId trim 1–120, default mobile-app. |
| Código y refresh | code: string trim de seis dígitos. refreshToken: string trim 1–4096; ese cuerpo rechaza campos extra. Los demás flujos usan la misma validación de email. |

- Usuario: id, nombre, email, telefono, is_verified, estado_cuenta, fecha_registro, last_login_at; login añade rol. Sesión: id, deviceId enmascarado, creadoEn, expiraEn, isCurrent; sin token/hash.
- SMTP puede fallar con respuesta exitosa: revisar verificationEmailSent o sent; no confirman entrega.
- Renovar reemplaza el refresh token. Logout rechaza reutilizaciones; la sesión actual se revoca con logout. La actividad válida renueva inactividad.
- Verificar limpia verification_code_*; reset revoca sesiones. Contraseñas/códigos se guardan como hashes.
- 10 solicitudes/15 minutos por contador separado de register, verify, resend, forgot y reset. Login cuenta solo fallos; refresh/logout/sesiones no consumen ese contador. Headers draft-8. Mensaje: “Demasiados intentos de inicio de sesión. Intenta nuevamente en unos minutos.”

## Salud y catálogos (7)

[Rutas públicas](../src/modules/catalogos/catalogos.routes.js) y [privadas](../src/modules/pets/pets.routes.js).

| Método | Ruta | Función | Acceso | Parámetros | Devuelve (200) | Errores relevantes |
|---|---|---|---|---|---|---|
| GET | /api/health | Comprobar respuesta de API | Público | — | {ok:true,message:"API funcionando"} | No comprueba dependencias |
| GET | /api/catalogos/especies | Listar especies | Público | — | especies=[{id,nombre}] | 500 |
| GET | /api/catalogos/razas/:especieId | Listar razas de especie | Público | :especieId | razas=[{id,nombre,fk_especie}] | Puede dar 500 con ID inválido |
| GET | /api/catalogos/sexos | Listar sexos | Público | — | sexos=[{id,nombre}] | Comunes |
| GET | /api/pets/especies | Listar especies | Sesión | — | especies=[{id,nombre}] | 500 |
| GET | /api/pets/razas/:especieId | Listar razas de especie | Sesión | :especieId | razas=[{id,nombre,fk_especie}] | Puede dar 500 con ID inválido |
| GET | /api/pets/sexos | Listar sexos | Sesión | — | sexos=[{id,nombre}] | Comunes |

Sexos: MACHO, HEMBRA, NO_DEFINIDO. Una lista vacía responde 200.

## Mascotas y fotos (11)

[Registro](../src/modules/pets/mascotas.routes.js) y [otras rutas](../src/modules/pets/pets.routes.js). Solo mascotas y fotos propias.

| Método | Ruta | Función | Acceso | Recibe | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| POST | /api/pets | Registrar mascota | Sesión | Multipart: datos + imagenes + foto_principal_index | 201: message, mascotaId, imagenesGuardadas | 400 datos/fotos |
| GET | /api/pets/my | Listar propias | Sesión | — | total, mascotas con fotoPrincipal | Comunes |
| GET | /api/pets/:id | Consultar detalle | Sesión | :id | mascota | 404 |
| PUT | /api/pets/:id | Editar datos | Sesión | :id; datos de mascota | message, mascota | 400; 404 |
| DELETE | /api/pets/:id | Inactivar mascota | Sesión | :id; sin cuerpo | message, imagenesEliminadas; ya INACTIVA: message | 404; 409 ACTIVE_REPORT_EXISTS |
| GET | /api/pets/images/:imageId | Consultar foto | Sesión | :imageId | Bytes; caché private, max-age=86400 | 400; 404 |
| GET | /api/pets/:id/images | Listar fotos | Sesión | :id | total, imagenes | 404 |
| POST | /api/pets/:id/images | Agregar fotos | Sesión | Multipart: imagenes, marcar_como_principal?, foto_principal_index? | 201: message, total agregado | 400; 404 |
| PUT | /api/pets/:id/images/batch | Guardar galería | Sesión | Multipart LoteFotos | message, total final | 400; 404; 409 |
| PUT | /api/pets/:id/images/:imageId/principal | Cambiar principal | Sesión | IDs; sin cuerpo requerido | message | 400; 404 |
| DELETE | /api/pets/:id/images/:imageId | Eliminar foto | Sesión | IDs; sin cuerpo | message | 404; 409 mínimo/principal |

**Datos:** fk_especie positivo; nombre/color trim no vacíos; fk_raza opcional/null y de esa especie. edad_aprox entero no negativo, ausente/vacío al crear → null; al editar no omitir: enviar número, null o vacío. unidad_edad MESES/ANIOS, otro → null; sexo MACHO/HEMBRA/NO_DEFINIDO, otro → NO_DEFINIDO; observaciones trim o null.

**Fotos:** campo repetido imagenes, no imagenes[]. JPEG/PNG/WEBP, MIME/firma válidos, máximo 5 MiB cada una. Registro: 15–30 e índice principal desde cero. Agregar: 1–30; marcar_como_principal=true (boolean/texto) exige índice; false/ausente conserva principal.

**LoteFotos:** original_image_ids y retained_image_ids: textos JSON de arrays de ObjectIds únicos; ausentes/vacíos → []. retained es subconjunto de original, que debe coincidir con galería actual. Hasta 30 nuevas imagenes. Una principal: principal_existing_id retenida o principal_new_index nueva. Mínimo 15 finales, sin duplicados por contenido.

Mascota conserva nombres SQL; listado añade fotoPrincipal={id,url} o null. Fotos: id=storage_ref, metadataId, storageRef, url, esPrincipal, fecha; principal primero, luego fecha.

409 en lote: galería cambió, duplicados, inconsistencia o MINIMUM_PET_PHOTOS_REQUIRED. Borrar con 15 fotos/principal inconsistente: 409. Al borrar principal se elige reemplazo.

Eliminar conserva mascota/foto_mascota, marca INACTIVA y elimina imágenes; reporte ACTIVO lo bloquea. Recuperación incompleta: 500. Ver [recuperación](../src/modules/pets/README.deletion-recovery.md).

## Perfil (4)

[Rutas](../src/modules/profile/profile.routes.js). Solo perfil propio.

| Método | Ruta | Función | Acceso | Recibe | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| GET | /api/profile | Consultar perfil | Sesión | — | data=Perfil | 404 |
| PATCH | /api/profile | Editar perfil | Sesión | JSON {nombre?,telefono?} | message, data=Perfil | 400; 404; 415 |
| POST | /api/profile/photo | Reemplazar foto | Sesión | Multipart: un archivo foto | message, data=Perfil | 400; 404 |
| GET | /api/profile/photo/:imageId | Consultar foto actual | Sesión | :imageId propio y vigente | Bytes; caché private, no-store | 404 |

Perfil: id, nombre, email, telefono, foto_url nullable, notificaciones_activas. PATCH: al menos un editable, sin extras ni email; nombre/teléfono según registro. Foto JPG/JPEG/PNG/WEBP, extensión/MIME/firma válidos, hasta 5 MiB; reemplaza anterior.

## Reportes e historial (7)

[Rutas](../src/modules/reports/reports.routes.js) y [validaciones](../src/modules/reports/reports.schemas.js). Solo reportes propios; ajenos devuelven 404.

| Método | Ruta | Función | Acceso | Recibe | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| GET | /api/reports/pets | Listar mascotas reportables | Sesión | — | total, pets | Comunes |
| GET | /api/reports/my | Listar reportes propios | Sesión | — | total, reports | Comunes |
| GET | /api/reports/:id | Consultar reporte | Sesión | :id | report | 404 |
| POST | /api/reports | Crear pérdida | Sesión | JSON {mascotaId,descripcion?,mostrarContacto?,ubicacion} | 201: message, report={id,estado,creado_en} | 404 mascota; 409 activo duplicado; 422 |
| PATCH | /api/reports/:id | Editar reporte activo | Sesión | JSON con descripcion, mostrarContacto y/o ubicacion | message, report={id,estado,actualizadoEn} | 404; 409 finalizado/inconsistencia; 422 |
| POST | /api/reports/:id/close | Finalizar reporte | Sesión | :id; sin cuerpo requerido | message, report={id,estado,cerradoEn} | 404; 409 finalizado/inconsistencia |
| GET | /api/reports/:reportId/sightings | Consultar historial | Sesión | :reportId; period? | report, period, total, filteredTotal, sightings | 400 período; 404 |

- Entrada: mascotaId positivo; descripcion opcional/null, trim hasta 2000; mostrarContacto boolean, default false. PATCH exige un campo; ubicación según reglas comunes.
- Crear: mascota propia no INACTIVA, sin otro ACTIVO; guarda reporte ACTIVO, ubicación y mascota PERDIDA juntos. Editar actualiza actualizado_en y revalida ubicación.
- Cerrar: FINALIZADO/cerrado_en y mascota ACTIVA, en una transacción. Repetir cierre o inconsistencia de mascota/ubicación/fechas → 409.
- Mascota reportable: id, nombre, especie, raza, estado, tieneReporteActivo, fotoPrincipal={id,url} o null. Excluye INACTIVA; señala reportes activos.
- Reporte: id, mascotaId, descripcion, mostrarContacto, estado, creadoEn, actualizadoEn, cerradoEn, avistamientosCount; mascota={id,nombre,especie,raza,estado,fotoPrincipal}; ubicacion={metodo,lat,lng,precisionM,referencia,direccion,placeId}.
- Historial: period ALL (default)/TODAY/7D/30D. report={id,estado,mascota,fotoPrincipal,ubicacionPerdida}. total cuenta por reportId; filteredTotal aplica período. sightings: más reciente primero, ubicación y foto opcional. Admite ACTIVO/FINALIZADO y vacío; nunca mezcla reportes por mascota.

## Avistamientos (4)

[Rutas](../src/modules/sightings/sightings.routes.js) y [validaciones](../src/modules/sightings/sightings.schemas.js).

| Método | Ruta | Función | Acceso | Recibe | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| GET | /api/sightings/linkable-reports | Listar pérdidas vinculables | Público | — | total, reports | Comunes |
| GET | /api/sightings/:id | Consultar avistamiento | Público | :id | sighting | 404 |
| GET | /api/sightings/images/:imageId | Consultar foto | Público | :imageId | Bytes; caché public, max-age=3600 | 404 |
| POST | /api/sightings | Registrar avistamiento | Sesión | Multipart: datos y foto? | 201: message, sighting | 400; 404 reporte; 409 no vinculable; 422 |

descripcion trim 1–2000; reportId positivo u opcional/null/vacío → null. Ubicación según reglas comunes, sin extras. foto: 0 o 1, JPG/JPEG/PNG/WEBP, extensión/MIME/firma válidos, máximo 5 MiB. Hasta 8 campos de texto, 10 KB cada uno.

Respuesta: id, descripcion, fechaHora (Z), ubicacion={metodo,lat,lng,precisionM,direccion,placeId}, foto={id,url} o null, vinculado, reporte={id,mascota:{nombre,especie,raza}} o null.

Permite vincular a reporte ajeno ACTIVO con mascota PERDIDA; si no cumple, 409. Vinculables: id y mascota={nombre,especie,raza,fotoPrincipal}, foto pública del mapa. Nunca expone autor/email/teléfono/userId. Fecha del servidor, estado NULL; independiente no crea mascota/reporte.

## Mapa (2)

[Rutas](../src/modules/map/map.routes.js) y [filtros](../src/modules/map/map.filters.js).

| Método | Ruta | Función | Acceso | Recibe | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| GET | /api/map/reports | Consultar marcadores | Opcional | Query species?, color?, from?, to?, status? | total, data=[Marcador] | 400 INVALID_MAP_FILTERS; 401 |
| GET | /api/map/images/:imageId | Consultar imagen pública | Público | :imageId ObjectId | Bytes; caché no-store | 400; 404 |

species/color: trim 1–100, coincidencia exacta en minúsculas; independientes no coinciden. from/to: YYYY-MM-DD, from <= to, días completos en Bogotá. Compara creación de pérdidas, cierre de encontrados y fechaHora de avistamientos. status active/found; omitido incluye tipos disponibles.

| Tipo | Regla |
|---|---|
| lost | Reporte ACTIVO y mascota PERDIDA. |
| found | FINALIZADO, mascota no INACTIVA, cerrado_en >= ahora UTC - 30 días. Filtros de fecha no amplían esa ventana; también aplica a fotos públicas. |
| sighting | Avistamiento. status=found lo excluye; active puede incluir pérdidas y avistamientos. |

Marcador: id (lost_ o sighting_), title, petName, species/color cuando existen, details, location, reference, description, dateText, imageUrl, imageUrls, lat, lng, type. Reportes añaden createdDateText, closedDateText, isOwner, showContact, ownerPhone, ownerName, ownerEmail. Avistamientos: isLinked, linkedReportId, showContact=false, isOwner=false.

Contacto: teléfono de reporte ACTIVO ajeno con mostrar_contacto=true; resto showContact=false/ownerPhone vacío. ownerName/ownerEmail siempre vacíos; sin autor de avistamiento.

DIRECCION muestra dirección; GPS/MAPA, punto/referencia. Coordenadas coincidentes conservan IDs; found mantiene lost_. Fotos: referencia pública PostgreSQL y documento Mongo activo, sin acceso a fotos privadas.

## Geofence y direcciones (2)

[Geofence](../src/modules/geofence/geofence.service.js) y [Geocoding](../src/modules/geocoding/geocoding.service.js).

| Método | Ruta | Función | Acceso | Recibe (JSON) | Devuelve (200) | Errores relevantes |
|---|---|---|---|---|---|---|
| POST | /api/geofence/check | Validar zona | Sesión | {lat,lng} | {inside,allowed,mode,area}, sin ok | 400 |
| POST | /api/geocoding/address | Buscar dirección | Sesión | {address} | {ok:true,mode,area,candidates} | Tabla inferior |

Ambos rechazan campos extra. Coordenadas: rangos comunes. address trim 1–300. area={code:"006313",name:"Salitre Occidental"}.

Interior/borde/vértices permitidos. WARN conserva inside real y permite exterior; ENFORCE lo bloquea. Modo ausente/inválido → ENFORCE; solo configuración backend. Check responde 200; guardar ubicación revalida y puede dar 422 OUTSIDE_ALLOWED_AREA. Valida evento, sin segunda ubicación del usuario.

Google: solo backend, Colombia/español y bounds orientativo. Hasta 5 candidatos: {formattedAddress,lat,lng,placeId,locationType,inside,allowed}. ENFORCE: rechaza si ninguno interno; puede incluir externos no permitidos. WARN permite externos sin alterar coordenadas.

| Código | HTTP | Motivo |
|---|---|---|
| ADDRESS_REQUIRED | 400 | Cuerpo inválido o dirección vacía. |
| ADDRESS_NOT_FOUND | 404 | ZERO_RESULTS o lista vacía. |
| ADDRESS_OUTSIDE_ALLOWED_AREA | 422 | Ningún candidato dentro en ENFORCE. |
| INVALID_GEOCODING_RESPONSE | 502 | Estructura, metadatos o coordenadas inválidos del proveedor. |
| GEOCODING_NOT_CONFIGURED | 503 | Falta clave backend. |
| GEOCODING_UNAVAILABLE | 503 | Red, timeout o fallo del proveedor. |

Sin clave/URL secreta/respuesta cruda. Buscar no guarda. DIRECCION exige direccion/placeId/coordenadas y geofence; no vuelve a comprobar correspondencia con Google.

## Preferencias (2)

[Rutas](../src/modules/notification-preferences/notification-preferences.routes.js). Solo preferencias propias.

| Método | Ruta | Función | Acceso | Recibe | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| GET | /api/notification-preferences | Consultar preferencias | Sesión | — | data=Preferencias | 404 perfil |
| PATCH | /api/notification-preferences | Guardar preferencias | Sesión | JSON completo | message, data=Preferencias | 400; 404; 415 |

Siempre los cinco campos, sin extras: notificacionesActivas/soloMiZona boolean; especieFiltro Perro/Gato/null; tipoEvento PERDIDA/AVISTAMIENTO/ENCONTRADO/null; radioKm 1/2/5. PATCH no es parcial.

Lee notificaciones_activas del perfil; sin preferencias: radio 2, filtros null, soloMiZona=false. Guarda perfil/preferencias juntos; sin push.

## FAQ y categorías (11)

[Rutas](../src/modules/faq/faq.routes.js) y [servicio](../src/modules/faq/faq.service.js).

| Método | Ruta | Función | Acceso | Recibe | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| GET | /api/faqs | Listar activas | Público | Query categoriaId?, search? | data=[FAQ] | 400 categoría |
| GET | /api/faqs/:id | Consultar activa | Público | :id | data=FAQ | 404 |
| GET | /api/faqs/categories | Listar categorías | Público | — | data=[Categoría con contadores] | Comunes |
| GET | /api/faqs/admin | Listar todas | Administrador | Query categoriaId?, search? | data=[FAQ], incluye archivadas | 400 |
| POST | /api/faqs | Crear FAQ | Administrador | JSON {categoriaId,pregunta,respuesta,activa?} | 201: data=FAQ | 404 categoría; 409 duplicado |
| PUT | /api/faqs/:id | Editar FAQ | Administrador | JSON {categoriaId,pregunta,respuesta,activa} | data=FAQ | 404; 409 duplicado |
| PATCH | /api/faqs/:id/status | Archivar/reactivar | Administrador | JSON {activa:boolean} | data=FAQ | 404 |
| DELETE | /api/faqs/:id | Borrar FAQ | Administrador | :id; sin cuerpo | data={deleted:true,id} | 404 |
| POST | /api/faqs/categories | Crear categoría | Administrador | JSON {nombre,descripcion?} | 201: data=Categoría | 400 |
| PUT | /api/faqs/categories/:id | Editar categoría | Administrador | JSON {nombre,descripcion?} | data=Categoría | 400; 404 |
| DELETE | /api/faqs/categories/:id | Borrar categoría | Administrador | :id; sin cuerpo | data={deleted:true,id} | 404; 409 en uso |

categoriaId positivo; pregunta/respuesta trim no vacíos, sin máximo. activa default true; obligatoria al editar/status. Categoría: nombre trim 1–100; descripcion opcional/null/vacía → null o trim hasta 255.

FAQ: id, fk_categoria, pregunta, respuesta, activa; GET añade categoria. Categoría: id, nombre, descripcion; GET añade total_faq/total_activas.

search busca pregunta/respuesta. Archivada por ID → 404. DELETE físico; categoría con FAQ (incluso archivadas) → 409. Duplicado: categoría/pregunta iguales tras trim/minúsculas. Escrituras auditadas.

Códigos: 400 INVALID_ID/INVALID_FAQ_INPUT; 404 FAQ_NOT_FOUND/FAQ_CATEGORY_NOT_FOUND; 409 FAQ_DUPLICATE/FAQ_CATEGORY_IN_USE.

## Administración de usuarios (6)

[Rutas](../src/modules/users/users.routes.js) y [servicio](../src/modules/users/users.service.js).

| Método | Ruta | Función | Acceso | Recibe | Devuelve | Errores relevantes |
|---|---|---|---|---|---|---|
| GET | /api/users | Listar usuarios | Administrador | Query search?, estado?, rol? | data=[UsuarioAdmin] | 400 filtros |
| GET | /api/users/:id | Consultar usuario | Administrador | :id | data=UsuarioAdmin | 404 |
| POST | /api/users | Crear usuario | Administrador | JSON {nombre,email,password,telefono?,rol?} | 201: data=usuario + rol | 400; 409 email |
| PUT | /api/users/:id | Editar usuario | Administrador | JSON {nombre,email,rol,telefono?} | data=usuario + rol | 400; 404; 409 email |
| PATCH | /api/users/:id/status | Cambiar estado | Administrador | JSON {estado} | data=usuario actualizado | 404; 409 propia cuenta |
| DELETE | /api/users/:id | Eliminar lógicamente | Administrador | :id; sin cuerpo | data={deleted:true,logicalDelete:true,id} | 404; 409 propia cuenta |

nombre trim 1–150; email válido trim/minúsculas; telefono opcional/null/vacío → null, hasta 30 sin restricción de caracteres. rol USUARIO/ADMINISTRADOR, default USUARIO. Password trim 8–200, sin política del registro público. estado ACTIVO/SUSPENDIDO/ELIMINADO; rol/estado normalizados a mayúsculas.

search busca nombre/email/teléfono. UsuarioAdmin: id, nombre, email, telefono, is_verified, estado_cuenta, fecha_registro, last_login_at, rol. Escrituras pueden devolver menos campos, nunca contraseñas/hashes.

Crear: verificada/ACTIVA, acepta_tyc=true, perfil y rol. PUT no cambia contraseña/estado. Desactivar/eliminar revoca sesiones; DELETE conserva filas relacionadas. Prohibido desactivar/eliminar propia cuenta. Escrituras auditadas.

Códigos: 400 INVALID_USER_ID, INVALID_USER_INPUT, INVALID_EMAIL, INVALID_PHONE, INVALID_ROLE, INVALID_ACCOUNT_STATUS, INVALID_PASSWORD; 404 USER_NOT_FOUND; 409 EMAIL_ALREADY_EXISTS, CANNOT_DISABLE_SELF, CANNOT_DELETE_SELF; 500 ROLE_NOT_FOUND.

## Sesión y funciones pendientes

| HTTP | Códigos de sesión |
|---|---|
| 401 | ACCESS_TOKEN_REQUIRED, ACCESS_TOKEN_INVALID, ACCESS_TOKEN_EXPIRED, SESSION_REVOKED, SESSION_EXPIRED, REFRESH_TOKEN_INVALID, REFRESH_TOKEN_EXPIRED |
| 403 | ACCOUNT_INVALID, ACCOUNT_ROLE_INVALID, ROLE_FORBIDDEN |

No reintentar indefinidamente una sesión inválida ni reutilizar refresh tokens anteriores. Algunos 409 solo incluyen message; no exigir siempre code.

Pendientes: push, filtro geográfico del historial, reconocimiento y coincidencia manual. Sin edición/eliminación de avistamientos ni recuperación de fotos por HTTP. Scripts y HEAD/OPTIONS implícitos no cuentan entre las 66 operaciones.
