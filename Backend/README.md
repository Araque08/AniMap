# AniMap — Backend

AniMap permite registrar mascotas, reportar pérdidas y compartir avistamientos. Este backend ofrece la API REST que utiliza la app Flutter.

## Tecnologías y arquitectura

Usamos Flutter, Node.js con Express, PostgreSQL y MongoDB. El backend funciona como una sola aplicación organizada por módulos; no son microservicios.

```text
Flutter → API de Express (/api) → PostgreSQL y MongoDB
Flutter → Google Maps y GPS
Express → SMTP y Google Geocoding
```

Flutter se organiza en `Frontend/lib/features`: `data` contiene servicios y modelos; `presentation`, pantallas y widgets. `ApiConfig` centraliza `API_BASE_URL`; `SessionManager` gestiona restauración, renovación y cierre de sesión. La app nunca consulta las bases directamente.

En el backend, `src/server.js` inicia el servidor, `src/app.js` configura Express y `src/routes/index.js` monta las rutas.

| Carpeta en `src/modules` | Función |
|---|---|
| auth, profile | Cuentas, sesiones y perfil. |
| catalogos, pets | Catálogos, mascotas y fotos. |
| reports, sightings, map | Pérdidas, avistamientos, historial y mapa público. |
| geofence, geocoding | Zona permitida y búsqueda de direcciones. |
| notification-preferences | Preferencias de notificación. |
| faq, users | FAQ y administración de usuarios. |

Los módulos separan rutas, controladores, servicios y validaciones; Mascotas/Mapa también tienen lógica y SQL en routers. Comparten configuración y autenticación; administración exige rol.

PostgreSQL guarda los datos y referencias de fotos; MongoDB, las imágenes. No hay transacción conjunta: se compensan fallos. Las fotos eliminadas de mascotas tienen respaldo persistente; la recuperación requiere el [script documentado](src/modules/pets/README.deletion-recovery.md), que modifica datos.

Google Maps muestra mapas; GPS usa código nativo Android/iOS. El backend consulta Google Geocoding y envía correos con Nodemailer/SMTP. Cloud SQL y Atlas alojan las bases. Geofence usa el GeoJSON oficial local de Salitre Occidental.

## Requisitos e instalación

Necesitas Node.js, npm, acceso a PostgreSQL y MongoDB y las credenciales de desarrollo. Si usas Cloud SQL Auth Proxy en `127.0.0.1:15432`, inícialo antes del servidor.

Desde la raíz del proyecto:

```powershell
cd Backend
npm ci
```

## Configuración

Prepara `Backend/.env` siguiendo [.env.example](.env.example), sin sobrescribir una configuración existente. Completa las conexiones y secretos JWT; configura SMTP para correos y Google Geocoding para direcciones. No subas credenciales al repositorio.

## Ejecución

Desde `Backend`:

```powershell
npm run dev
```

También puedes usar `npm start` sin nodemon. El puerto predeterminado es 3000, configurable con `PORT`. Comprueba [localhost:3000/api/health](http://localhost:3000/api/health); esta ruta confirma que la API responde, no la disponibilidad de todas sus dependencias.

## Documentación y límites actuales

Consulta [API.md](docs/API.md) para las 66 operaciones, sus datos, permisos y errores.

Pendientes: push, coincidencia manual, reconocimiento por imagen y filtro geográfico del historial. Los módulos comparten dependencias; se prueban los relacionados tras cada cambio. El plazo de 48 horas requiere medición práctica.

Detalles de configuración actuales: `CORS_ORIGIN` no controla el CORS aplicado y `DB_SSL` activa TLS sin verificar el certificado. La API admite descripciones de reporte de hasta 2000 caracteres; Flutter limita el formulario a 1000.
