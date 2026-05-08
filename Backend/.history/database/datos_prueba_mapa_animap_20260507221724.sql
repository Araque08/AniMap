-- =========================================================
-- DATOS DE PRUEBA PARA EL MAPA DE ANIMAP
-- =========================================================
-- Este script inserta información mínima para probar:
-- 1. Mascotas perdidas
-- 2. Mascotas encontradas
-- 3. Avistamientos
--
-- Ejecutar en pgAdmin sobre la base: animap_db
-- =========================================================

-- =========================================================
-- USUARIOS DE PRUEBA
-- =========================================================
-- Aquí creo usuarios de prueba para que los reportes tengan dueño.
-- Uso ON CONFLICT para evitar errores si ya existen estos correos.
INSERT INTO usuario (
    nombre,
    email,
    telefono,
    password_hash,
    is_verified,
    acepta_tyc,
    estado_cuenta
)
VALUES
(
    'Felipe Quevedo',
    'felipe.mapa@test.com',
    '3001234567',
    'hash_temporal',
    TRUE,
    TRUE,
    'ACTIVO'
),
(
    'Laura Gomez',
    'laura.mapa@test.com',
    '3114567890',
    'hash_temporal',
    TRUE,
    TRUE,
    'ACTIVO'
),
(
    'Usuario Comunidad',
    'comunidad.mapa@test.com',
    '3229876543',
    'hash_temporal',
    TRUE,
    TRUE,
    'ACTIVO'
)
ON CONFLICT (email) DO NOTHING;

-- =========================================================
-- MASCOTAS DE PRUEBA
-- =========================================================
-- Aquí creo mascotas asociadas a usuarios.
-- fk_raza se deja NULL porque el script base puede no tener razas insertadas.
INSERT INTO mascota (
    fk_usuario,
    fk_especie,
    fk_raza,
    nombre,
    color,
    edad_aprox,
    unidad_edad,
    sexo,
    estado,
    observaciones
)
VALUES
(
    (SELECT id FROM usuario WHERE email = 'felipe.mapa@test.com'),
    (SELECT id FROM especie WHERE nombre = 'Perro'),
    NULL,
    'Max',
    'Dorado',
    3,
    'ANIOS',
    'MACHO',
    'PERDIDA',
    'Golden Retriever amigable, responde al nombre de Max.'
),
(
    (SELECT id FROM usuario WHERE email = 'laura.mapa@test.com'),
    (SELECT id FROM especie WHERE nombre = 'Gato'),
    NULL,
    'Luna',
    'Gris',
    18,
    'MESES',
    'HEMBRA',
    'PERDIDA',
    'Gata criolla con collar azul.'
),
(
    (SELECT id FROM usuario WHERE email = 'felipe.mapa@test.com'),
    (SELECT id FROM especie WHERE nombre = 'Perro'),
    NULL,
    'Pluto',
    'Café claro',
    4,
    'ANIOS',
    'MACHO',
    'ENCONTRADA',
    'Mascota recuperada por su dueño.'
);

-- =========================================================
-- REPORTES DE PRUEBA
-- =========================================================
-- Aquí creo dos reportes activos y un reporte finalizado.
-- ACTIVO se mostrará como mascota perdida.
-- FINALIZADO se mostrará como mascota encontrada.
INSERT INTO reporte (
    fk_usuario,
    fk_mascota,
    mostrar_contacto,
    descripcion,
    estado,
    creado_en,
    cerrado_en
)
VALUES
(
    (SELECT id FROM usuario WHERE email = 'felipe.mapa@test.com'),
    (SELECT id FROM mascota WHERE nombre = 'Max' ORDER BY id DESC LIMIT 1),
    TRUE,
    'Visto por última vez corriendo hacia la avenida. Parece asustado y responde al nombre de Max.',
    'ACTIVO',
    NOW() - INTERVAL '2 days',
    NULL
),
(
    (SELECT id FROM usuario WHERE email = 'laura.mapa@test.com'),
    (SELECT id FROM mascota WHERE nombre = 'Luna' ORDER BY id DESC LIMIT 1),
    TRUE,
    'Se perdió cerca al conjunto residencial. Tiene collar azul y suele esconderse en zonas verdes.',
    'ACTIVO',
    NOW() - INTERVAL '1 day',
    NULL
),
(
    (SELECT id FROM usuario WHERE email = 'felipe.mapa@test.com'),
    (SELECT id FROM mascota WHERE nombre = 'Pluto' ORDER BY id DESC LIMIT 1),
    FALSE,
    'El reporte fue finalizado porque el dueño confirmó que la mascota fue encontrada.',
    'FINALIZADO',
    NOW() - INTERVAL '5 days',
    NOW() - INTERVAL '3 days'
);

-- =========================================================
-- UBICACIONES DE REPORTES
-- =========================================================
-- Aquí asigno coordenadas reales aproximadas de Ciudad Salitre Occidental.
INSERT INTO ubicacion (
    fk_reporte,
    fk_avistamiento,
    metodo,
    lat,
    lng,
    precision_m,
    direccion,
    place_id
)
VALUES
(
    (SELECT r.id
     FROM reporte r
     INNER JOIN mascota m ON m.id = r.fk_mascota
     WHERE m.nombre = 'Max'
     ORDER BY r.id DESC
     LIMIT 1),
    NULL,
    'MAPA',
    4.6577000,
    -74.1082000,
    15,
    'Carrera 53, Ciudad Salitre Occidental',
    NULL
),
(
    (SELECT r.id
     FROM reporte r
     INNER JOIN mascota m ON m.id = r.fk_mascota
     WHERE m.nombre = 'Luna'
     ORDER BY r.id DESC
     LIMIT 1),
    NULL,
    'MAPA',
    4.6559000,
    -74.1112000,
    15,
    'Calle 24C, Ciudad Salitre Occidental',
    NULL
),
(
    (SELECT r.id
     FROM reporte r
     INNER JOIN mascota m ON m.id = r.fk_mascota
     WHERE m.nombre = 'Pluto'
     ORDER BY r.id DESC
     LIMIT 1),
    NULL,
    'MAPA',
    4.6565000,
    -74.1068000,
    15,
    'Pablo Andrade, Ciudad Salitre Occidental',
    NULL
);

-- =========================================================
-- AVISTAMIENTOS DE PRUEBA
-- =========================================================
-- Aquí creo avistamientos comunitarios que se verán en verde en el mapa.
INSERT INTO avistamiento (
    fk_usuario,
    fk_reporte_perdida,
    descripcion,
    fecha_hora,
    estado
)
VALUES
(
    (SELECT id FROM usuario WHERE email = 'comunidad.mapa@test.com'),
    NULL,
    'Fue visto caminando solo cerca de la zona verde. No tenía collar visible.',
    NOW() - INTERVAL '8 hours',
    'ACTIVO'
),
(
    (SELECT id FROM usuario WHERE email = 'comunidad.mapa@test.com'),
    NULL,
    'Visto cerca a la Carrera 60. Parece estar perdido y se mantiene cerca de los edificios.',
    NOW() - INTERVAL '3 hours',
    'ACTIVO'
);

-- =========================================================
-- UBICACIONES DE AVISTAMIENTOS
-- =========================================================
INSERT INTO ubicacion (
    fk_reporte,
    fk_avistamiento,
    metodo,
    lat,
    lng,
    precision_m,
    direccion,
    place_id
)
VALUES
(
    NULL,
    (SELECT id
     FROM avistamiento
     WHERE descripcion LIKE 'Fue visto caminando solo%'
     ORDER BY id DESC
     LIMIT 1),
    'MAPA',
    4.6586000,
    -74.1101000,
    15,
    'Parque Ciudad Salitre',
    NULL
),
(
    NULL,
    (SELECT id
     FROM avistamiento
     WHERE descripcion LIKE 'Visto cerca a la Carrera 60%'
     ORDER BY id DESC
     LIMIT 1),
    'MAPA',
    4.6549000,
    -74.1078000,
    15,
    'Carrera 60, Ciudad Salitre Occidental',
    NULL
);

-- =========================================================
-- CONSULTA DE VERIFICACIÓN
-- =========================================================
-- Esta consulta permite verificar cuántos datos quedaron para el mapa.
SELECT
    (SELECT COUNT(*) FROM reporte) AS total_reportes,
    (SELECT COUNT(*) FROM avistamiento) AS total_avistamientos,
    (SELECT COUNT(*) FROM ubicacion) AS total_ubicaciones;
