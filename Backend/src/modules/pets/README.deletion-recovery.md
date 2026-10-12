# Recuperación de eliminación de fotos

`PetPhotoDeletionRecovery` es una colección privada del MongoDB existente.
Guarda una cabecera por operación y una copia BSON por foto, incluyendo su ID,
contenido, metadatos y principal. No tiene endpoint público ni TTL automático.

Antes del borrado se releen todas las copias y se verifica su SHA-256 BSON.
Las escrituras del respaldo y del borrado utilizan confirmación `majority`.
El bloqueo de la mascota en PostgreSQL serializa eliminación y reconciliación.
No se crea otro respaldo de una mascota con una operación pendiente.

Tras un fallo, la recuperación usa una conexión PostgreSQL nueva:

- Estado original confirmado: inserta únicamente originales faltantes y verifica
  todo el manifiesto. Nunca sobrescribe fotos modificadas ni datos de otro dueño.
- `INACTIVA` confirmado: completa el borrado exclusivamente de IDs respaldados.
- Estado desconocido, contenido distinto o recuperación incompleta: conserva
  el respaldo y registra `PET_PHOTO_RECOVERY_PENDING` con `operationId` y código.

La cabecera se elimina al final. Una limpieza interrumpida puede reintentarse.
Una operación ya resuelta puede ejecutarse nuevamente sin duplicar imágenes.

## Después de reiniciar

Desde `Backend`, con su configuración local habitual, un operador autorizado
puede recuperar **una sola operación** usando el UUID del log:

`node scripts/recover-pet-deletion.js <operationId>`

El comando puede restaurar/borrar exclusivamente los originales de esa operación;
no es una comprobación de solo lectura. No ejecutarlo contra datos reales sin
autorización. No hay recuperación masiva ni tareas automáticas al iniciar.

## Almacenamiento

Una operación requiere temporalmente aproximadamente un juego adicional de fotos
más metadatos: 15 fotos de 5 MiB requieren unos 75 MiB adicionales; 30, unos 150 MiB.
El consumo real se registra en `bytes` de la cabecera, sin incluir contenido en logs.
La copia se libera tras verificar la consistencia. Si falta espacio al respaldar,
no se borran originales. Las operaciones pendientes conservan espacio hasta su
reconciliación; revisar estos casos antes de que se acumulen, sin borrarlas por edad.

No existe una transacción distribuida entre PostgreSQL y MongoDB. El journal permite
recuperación tras reinicio, pero una caída de MongoDB requiere esperar disponibilidad.
La pérdida del propio almacenamiento MongoDB requiere respaldos del proveedor.
