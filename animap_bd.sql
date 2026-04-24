-- =========================================================
-- AniMap - Script PostgreSQL basado en el diagrama de clases actual
-- =========================================================

-- =========================
-- LIMPIEZA INICIAL
-- =========================
DROP TABLE IF EXISTS coincidencia_reconocimiento CASCADE;
DROP TABLE IF EXISTS bitacora_administrativa CASCADE;
DROP TABLE IF EXISTS ubicacion CASCADE;
DROP TABLE IF EXISTS foto_avistamiento CASCADE;
DROP TABLE IF EXISTS avistamiento CASCADE;
DROP TABLE IF EXISTS notificacion CASCADE;
DROP TABLE IF EXISTS reporte CASCADE;
DROP TABLE IF EXISTS foto_mascota CASCADE;
DROP TABLE IF EXISTS mascota CASCADE;
DROP TABLE IF EXISTS raza CASCADE;
DROP TABLE IF EXISTS especie CASCADE;
DROP TABLE IF EXISTS faq CASCADE;
DROP TABLE IF EXISTS categoria_faq CASCADE;
DROP TABLE IF EXISTS preferencia_notificacion CASCADE;
DROP TABLE IF EXISTS device_session CASCADE;
DROP TABLE IF EXISTS usuario_rol CASCADE;
DROP TABLE IF EXISTS rol CASCADE;
DROP TABLE IF EXISTS perfil CASCADE;
DROP TABLE IF EXISTS usuario CASCADE;

DROP TYPE IF EXISTS metodo_ubicacion_enum CASCADE;
DROP TYPE IF EXISTS estado_reporte_enum CASCADE;
DROP TYPE IF EXISTS estado_mascota_enum CASCADE;
DROP TYPE IF EXISTS estado_usuario_enum CASCADE;
DROP TYPE IF EXISTS sexo_mascota_enum CASCADE;
DROP TYPE IF EXISTS estado_coincidencia_enum CASCADE;

-- =========================
-- ENUMS
-- =========================
CREATE TYPE metodo_ubicacion_enum AS ENUM ('GPS', 'DIRECCION', 'MAPA');
CREATE TYPE estado_reporte_enum AS ENUM ('ACTIVO', 'FINALIZADO');
CREATE TYPE estado_mascota_enum AS ENUM ('ACTIVA', 'PERDIDA', 'ENCONTRADA', 'INACTIVA');
CREATE TYPE estado_usuario_enum AS ENUM ('ACTIVO', 'SUSPENDIDO', 'ELIMINADO');
CREATE TYPE sexo_mascota_enum AS ENUM ('MACHO', 'HEMBRA', 'NO_DEFINIDO');
CREATE TYPE estado_coincidencia_enum AS ENUM ('PENDIENTE', 'VALIDADA', 'DESCARTADA');

-- =========================
-- USUARIO / CUENTA
-- =========================
CREATE TABLE usuario (
    id                             SERIAL PRIMARY KEY,
    nombre                         VARCHAR(120) NOT NULL,
    email                          VARCHAR(150) NOT NULL UNIQUE,
    telefono                       VARCHAR(20) NOT NULL,
    password_hash                  VARCHAR(255) NOT NULL,
    is_verified                    BOOLEAN NOT NULL DEFAULT FALSE,
    acepta_tyc                     BOOLEAN NOT NULL DEFAULT FALSE,
    estado_cuenta                  estado_usuario_enum NOT NULL DEFAULT 'ACTIVO',
    verification_code_hash         VARCHAR(255),
    verification_code_expires_at   TIMESTAMP,
    verification_code_sent_at      TIMESTAMP,
    fecha_registro                 TIMESTAMP NOT NULL DEFAULT NOW(),
    last_login_at                  TIMESTAMP,
    CONSTRAINT chk_usuario_email_formato
        CHECK (POSITION('@' IN email) > 1)
);

CREATE TABLE perfil (
    id                        SERIAL PRIMARY KEY,
    fk_usuario                INT NOT NULL UNIQUE,
    foto_url                  VARCHAR(500),
    foto_storage_ref          VARCHAR(255),
    notificaciones_activas    BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_perfil_usuario
        FOREIGN KEY (fk_usuario) REFERENCES usuario(id) ON DELETE CASCADE
);

CREATE TABLE rol (
    id         SERIAL PRIMARY KEY,
    nombre     VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE usuario_rol (
    fk_usuario   INT NOT NULL,
    fk_rol       INT NOT NULL,
    PRIMARY KEY (fk_usuario, fk_rol),
    CONSTRAINT fk_usuario_rol_usuario
        FOREIGN KEY (fk_usuario) REFERENCES usuario(id) ON DELETE CASCADE,
    CONSTRAINT fk_usuario_rol_rol
        FOREIGN KEY (fk_rol) REFERENCES rol(id) ON DELETE RESTRICT
);

CREATE TABLE device_session (
    id                   SERIAL PRIMARY KEY,
    fk_usuario           INT NOT NULL,
    device_id            VARCHAR(120) NOT NULL,
    refresh_token_hash   VARCHAR(255) NOT NULL,
    creado_en            TIMESTAMP NOT NULL DEFAULT NOW(),
    expira_en            TIMESTAMP NOT NULL,
    vigente              BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_device_session_usuario
        FOREIGN KEY (fk_usuario) REFERENCES usuario(id) ON DELETE CASCADE,
    CONSTRAINT chk_device_session_fechas
        CHECK (expira_en > creado_en)
);

CREATE TABLE preferencia_notificacion (
    id                 SERIAL PRIMARY KEY,
    fk_usuario         INT NOT NULL UNIQUE,
    radio_km           NUMERIC(6,2) NOT NULL DEFAULT 2.00,
    especie_filtro     VARCHAR(80),
    tipo_evento        VARCHAR(50),
    solo_mi_zona       BOOLEAN NOT NULL DEFAULT FALSE,
    actualizada_en     TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_preferencia_usuario
        FOREIGN KEY (fk_usuario) REFERENCES usuario(id) ON DELETE CASCADE,
    CONSTRAINT chk_preferencia_radio
        CHECK (radio_km >= 0)
);

-- =========================
-- FAQ
-- =========================
CREATE TABLE categoria_faq (
    id             SERIAL PRIMARY KEY,
    nombre         VARCHAR(100) NOT NULL UNIQUE,
    descripcion    VARCHAR(255)
);

CREATE TABLE faq (
    id              SERIAL PRIMARY KEY,
    fk_categoria    INT NOT NULL,
    pregunta        TEXT NOT NULL,
    respuesta       TEXT NOT NULL,
    activa          BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_faq_categoria
        FOREIGN KEY (fk_categoria) REFERENCES categoria_faq(id) ON DELETE RESTRICT
);

-- =========================
-- CATÁLOGOS Y MASCOTAS
-- =========================
CREATE TABLE especie (
    id         SERIAL PRIMARY KEY,
    nombre     VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE raza (
    id         SERIAL PRIMARY KEY,
    nombre     VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE mascota (
    id                SERIAL PRIMARY KEY,
    fk_usuario        INT NOT NULL,
    fk_especie        INT NOT NULL,
    fk_raza           INT,
    nombre            VARCHAR(120) NOT NULL,
    color             VARCHAR(100) NOT NULL,
    edad_aprox        INT,
    unidad_edad       VARCHAR(10),
    sexo              sexo_mascota_enum NOT NULL DEFAULT 'NO_DEFINIDO',
    estado            estado_mascota_enum NOT NULL DEFAULT 'ACTIVA',
    observaciones     TEXT,
    fecha_registro    TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_mascota_usuario
        FOREIGN KEY (fk_usuario) REFERENCES usuario(id) ON DELETE CASCADE,
    CONSTRAINT fk_mascota_especie
        FOREIGN KEY (fk_especie) REFERENCES especie(id) ON DELETE RESTRICT,
    CONSTRAINT fk_mascota_raza
        FOREIGN KEY (fk_raza) REFERENCES raza(id) ON DELETE SET NULL,
    CONSTRAINT chk_mascota_edad_aprox
        CHECK (edad_aprox IS NULL OR edad_aprox >= 0),
    CONSTRAINT chk_mascota_unidad_edad
        CHECK (
            unidad_edad IS NULL
            OR unidad_edad IN ('MESES', 'ANIOS')
        )
);

CREATE TABLE foto_mascota (
    id              SERIAL PRIMARY KEY,
    fk_mascota      INT NOT NULL,
    storage_ref     VARCHAR(255) NOT NULL,
    url_preview     VARCHAR(500),
    es_principal    BOOLEAN NOT NULL DEFAULT FALSE,
    fecha           TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_foto_mascota_mascota
        FOREIGN KEY (fk_mascota) REFERENCES mascota(id) ON DELETE CASCADE
);

-- =========================
-- REPORTES / AVISTAMIENTOS
-- =========================
CREATE TABLE reporte (
    id                  SERIAL PRIMARY KEY,
    fk_usuario          INT NOT NULL,
    fk_mascota          INT NOT NULL,
    mostrar_contacto    BOOLEAN NOT NULL DEFAULT FALSE,
    descripcion         TEXT,
    estado              estado_reporte_enum NOT NULL DEFAULT 'ACTIVO',
    creado_en           TIMESTAMP NOT NULL DEFAULT NOW(),
    cerrado_en          TIMESTAMP,
    CONSTRAINT fk_reporte_usuario
        FOREIGN KEY (fk_usuario) REFERENCES usuario(id) ON DELETE CASCADE,
    CONSTRAINT fk_reporte_mascota
        FOREIGN KEY (fk_mascota) REFERENCES mascota(id) ON DELETE CASCADE,
    CONSTRAINT chk_reporte_fechas
        CHECK (cerrado_en IS NULL OR cerrado_en >= creado_en)
);

CREATE TABLE notificacion (
    id               SERIAL PRIMARY KEY,
    fk_usuario       INT NOT NULL,
    fk_reporte       INT,
    titulo           VARCHAR(140) NOT NULL,
    mensaje          TEXT NOT NULL,
    leida            BOOLEAN NOT NULL DEFAULT FALSE,
    fecha            TIMESTAMP NOT NULL DEFAULT NOW(),
    tipo             VARCHAR(50),
    estado_envio     VARCHAR(50),
    audiencia        VARCHAR(50),
    CONSTRAINT fk_notificacion_usuario
        FOREIGN KEY (fk_usuario) REFERENCES usuario(id) ON DELETE CASCADE,
    CONSTRAINT fk_notificacion_reporte
        FOREIGN KEY (fk_reporte) REFERENCES reporte(id) ON DELETE SET NULL
);

CREATE TABLE avistamiento (
    id                    SERIAL PRIMARY KEY,
    fk_usuario            INT NOT NULL,
    fk_reporte_perdida    INT,
    descripcion           TEXT,
    fecha_hora            TIMESTAMP NOT NULL DEFAULT NOW(),
    estado                VARCHAR(50),
    CONSTRAINT fk_avistamiento_usuario
        FOREIGN KEY (fk_usuario) REFERENCES usuario(id) ON DELETE CASCADE,
    CONSTRAINT fk_avistamiento_reporte
        FOREIGN KEY (fk_reporte_perdida) REFERENCES reporte(id) ON DELETE SET NULL
);

CREATE TABLE foto_avistamiento (
    id                 SERIAL PRIMARY KEY,
    fk_avistamiento    INT NOT NULL,
    storage_ref        VARCHAR(255) NOT NULL,
    url_preview        VARCHAR(500),
    fecha              TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_foto_avistamiento_avistamiento
        FOREIGN KEY (fk_avistamiento) REFERENCES avistamiento(id) ON DELETE CASCADE
);

CREATE TABLE coincidencia_reconocimiento (
    id                       SERIAL PRIMARY KEY,
    fk_foto_avistamiento     INT NOT NULL,
    fk_foto_mascota          INT NOT NULL,
    similitud                NUMERIC(5,2) NOT NULL,
    umbral_usado             NUMERIC(5,2) NOT NULL,
    estado                   estado_coincidencia_enum NOT NULL DEFAULT 'PENDIENTE',
    creado_en                TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_coincidencia_foto_avistamiento
        FOREIGN KEY (fk_foto_avistamiento) REFERENCES foto_avistamiento(id) ON DELETE CASCADE,
    CONSTRAINT fk_coincidencia_foto_mascota
        FOREIGN KEY (fk_foto_mascota) REFERENCES foto_mascota(id) ON DELETE CASCADE,
    CONSTRAINT chk_coincidencia_similitud
        CHECK (similitud >= 0 AND similitud <= 100),
    CONSTRAINT chk_coincidencia_umbral
        CHECK (umbral_usado >= 0 AND umbral_usado <= 100)
);

-- =========================
-- UBICACIÓN
-- =========================
CREATE TABLE ubicacion (
    id                 SERIAL PRIMARY KEY,
    fk_reporte         INT UNIQUE,
    fk_avistamiento    INT UNIQUE,
    metodo             metodo_ubicacion_enum NOT NULL,
    lat                NUMERIC(10,7),
    lng                NUMERIC(10,7),
    precision_m        NUMERIC(8,2),
    direccion          VARCHAR(255),
    place_id           VARCHAR(150),
    "timestamp"        TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_ubicacion_reporte
        FOREIGN KEY (fk_reporte) REFERENCES reporte(id) ON DELETE CASCADE,
    CONSTRAINT fk_ubicacion_avistamiento
        FOREIGN KEY (fk_avistamiento) REFERENCES avistamiento(id) ON DELETE CASCADE,
    CONSTRAINT chk_ubicacion_referencia
        CHECK (
            (fk_reporte IS NOT NULL AND fk_avistamiento IS NULL)
            OR
            (fk_reporte IS NULL AND fk_avistamiento IS NOT NULL)
        ),
    CONSTRAINT chk_ubicacion_lat
        CHECK (lat IS NULL OR (lat >= -90 AND lat <= 90)),
    CONSTRAINT chk_ubicacion_lng
        CHECK (lng IS NULL OR (lng >= -180 AND lng <= 180)),
    CONSTRAINT chk_ubicacion_precision
        CHECK (precision_m IS NULL OR precision_m >= 0),
    CONSTRAINT chk_ubicacion_datos_minimos
        CHECK (
            (
                metodo IN ('GPS', 'MAPA')
                AND lat IS NOT NULL
                AND lng IS NOT NULL
            )
            OR
            (
                metodo = 'DIRECCION'
                AND direccion IS NOT NULL
            )
        )
);

-- =========================
-- BITÁCORA
-- =========================
CREATE TABLE bitacora_administrativa (
    id                      SERIAL PRIMARY KEY,
    fk_admin                INT NOT NULL,
    modulo                  VARCHAR(100) NOT NULL,
    accion                  VARCHAR(100) NOT NULL,
    entidad_afectada        VARCHAR(100) NOT NULL,
    id_entidad_afectada     INT,
    motivo                  VARCHAR(255),
    detalle                 TEXT,
    fecha_hora              TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_bitacora_admin
        FOREIGN KEY (fk_admin) REFERENCES usuario(id) ON DELETE RESTRICT
);

-- =========================
-- ÍNDICES Y REGLAS EXTRA
-- =========================
CREATE INDEX idx_usuario_email ON usuario(email);
CREATE INDEX idx_device_session_usuario ON device_session(fk_usuario);
CREATE INDEX idx_notificacion_usuario_leida ON notificacion(fk_usuario, leida);

CREATE INDEX idx_mascota_usuario ON mascota(fk_usuario);
CREATE INDEX idx_mascota_especie ON mascota(fk_especie);
CREATE INDEX idx_mascota_raza ON mascota(fk_raza);
CREATE INDEX idx_mascota_estado ON mascota(estado);

CREATE INDEX idx_foto_mascota_mascota ON foto_mascota(fk_mascota);
CREATE INDEX idx_reporte_usuario ON reporte(fk_usuario);
CREATE INDEX idx_reporte_mascota ON reporte(fk_mascota);
CREATE INDEX idx_reporte_estado ON reporte(estado);
CREATE INDEX idx_avistamiento_usuario ON avistamiento(fk_usuario);
CREATE INDEX idx_avistamiento_reporte ON avistamiento(fk_reporte_perdida);
CREATE INDEX idx_foto_avistamiento_avistamiento ON foto_avistamiento(fk_avistamiento);
CREATE INDEX idx_ubicacion_reporte ON ubicacion(fk_reporte);
CREATE INDEX idx_ubicacion_avistamiento ON ubicacion(fk_avistamiento);
CREATE INDEX idx_faq_categoria ON faq(fk_categoria);
CREATE INDEX idx_bitacora_admin_fecha ON bitacora_administrativa(fk_admin, fecha_hora);

-- una sola foto principal por mascota
CREATE UNIQUE INDEX uq_foto_mascota_principal
    ON foto_mascota(fk_mascota)
    WHERE es_principal = TRUE;

-- un solo reporte activo por mascota
CREATE UNIQUE INDEX uq_reporte_activo_por_mascota
    ON reporte(fk_mascota)
    WHERE estado = 'ACTIVO';

-- una sola sesión vigente por usuario y dispositivo
CREATE UNIQUE INDEX uq_device_session_activa_por_dispositivo
    ON device_session(fk_usuario, device_id)
    WHERE vigente = TRUE;

-- =========================
-- TRIGGERS ÚTILES
-- =========================

-- asigna foto principal por defecto si es la primera de la mascota
CREATE OR REPLACE FUNCTION fn_asignar_foto_principal_por_defecto()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM foto_mascota
        WHERE fk_mascota = NEW.fk_mascota
          AND es_principal = TRUE
    ) THEN
        NEW.es_principal := TRUE;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_asignar_foto_principal_por_defecto
BEFORE INSERT ON foto_mascota
FOR EACH ROW
EXECUTE FUNCTION fn_asignar_foto_principal_por_defecto();

-- completa cerrado_en cuando el reporte pasa a FINALIZADO
CREATE OR REPLACE FUNCTION fn_set_cerrado_en_reporte()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado = 'FINALIZADO' AND NEW.cerrado_en IS NULL THEN
        NEW.cerrado_en := NOW();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_cerrado_en_reporte
BEFORE UPDATE ON reporte
FOR EACH ROW
EXECUTE FUNCTION fn_set_cerrado_en_reporte();

-- actualiza timestamp de preferencia de notificación
CREATE OR REPLACE FUNCTION fn_set_actualizada_en_preferencia()
RETURNS TRIGGER AS $$
BEGIN
    NEW.actualizada_en := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_actualizada_en_preferencia
BEFORE UPDATE ON preferencia_notificacion
FOR EACH ROW
EXECUTE FUNCTION fn_set_actualizada_en_preferencia();

-- =========================
-- DATOS INICIALES BÁSICOS
-- =========================
INSERT INTO rol (nombre) VALUES
('ADMINISTRADOR'),
('USUARIO');

INSERT INTO especie (nombre) VALUES
('Perro'),
('Gato');

DELETE FROM usuario
WHERE email = 'felialej123@gmail.com';