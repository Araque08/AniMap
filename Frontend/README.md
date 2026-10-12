# animap

Aplicación de mascotas perdidas

## Backend configurable

La URL de API se define al ejecutar o compilar Flutter con `API_BASE_URL`.
Debe incluir `/api`. No hay una URL local predeterminada: si falta o es
inválida, la aplicación falla al iniciar con un mensaje de configuración.
En release se exige HTTPS.

Desde esta carpeta:

```powershell
# Android Emulator
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3000/api

# Android físico: reemplazar DEVICE_ID e IP-LAN-PC
flutter run -d <DEVICE_ID> --dart-define=API_BASE_URL=http://<IP-LAN-PC>:3000/api

# Backend público HTTPS, cuando exista
flutter run --dart-define=API_BASE_URL=https://<BACKEND_PUBLICO>/api
flutter build apk --release --dart-define=API_BASE_URL=https://<BACKEND_PUBLICO>/api

# Tests aislados, sin conectarse a este dominio
flutter test --dart-define=API_BASE_URL=https://api.animap.test:8443/api
```

Para pruebas LAN, PC y celular deben estar en la misma Wi-Fi y el backend
debe escuchar en `0.0.0.0:3000`. Desde el navegador del celular, comprobar
`http://<IP-LAN-PC>:3000/api/health`. `localhost`, `127.0.0.1` y `10.0.2.2`
no apuntan a la PC desde un teléfono físico. Si health no responde, revisar
manualmente firewall y aislamiento de la red; el código no los configura.
Mantener Cloud SQL Auth Proxy en `127.0.0.1:15432`: solo el backend necesita
acceder a él.

Android permite HTTP en debug/profile. Release tiene permiso INTERNET y
deshabilita tráfico HTTP sin cifrar.

Google Maps base usa la configuración Android y funciona de forma
independiente de las consultas de marcadores/fotos a la API de AniMap.
Para cada PC de desarrollo, revisar en Google Cloud el proyecto propietario
de la clave, Maps SDK for Android habilitado y la restricción Android de
`com.example.animap` junto con el SHA-1 del certificado debug de esa PC.
Para obtener las huellas de los builds actuales, ejecutar
`.\gradlew.bat signingReport` desde `android`. Maps SDK for Android usa
paquete + SHA-1; SHA-256 no sustituye esa restricción.
La migración de Cloud SQL no configura automáticamente Maps o Geocoding.
La firma release actual usa debug; definir una firma de distribución antes
de publicar y autorizar su certificado. No incluir claves en reportes o logs.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
