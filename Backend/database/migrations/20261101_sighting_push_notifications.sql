-- ANIMAP-35. Review and apply separately; this file is not run by the server.
BEGIN;

ALTER TABLE public.notificacion
  ADD COLUMN fk_avistamiento INTEGER REFERENCES public.avistamiento(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX uq_notificacion_avistamiento_destinatario
  ON public.notificacion (fk_avistamiento, fk_usuario)
  WHERE fk_avistamiento IS NOT NULL;

CREATE TABLE public.notificacion_entrega (
  id BIGSERIAL PRIMARY KEY,
  fk_notificacion INTEGER NOT NULL REFERENCES public.notificacion(id) ON DELETE CASCADE,
  fk_device_session INTEGER REFERENCES public.device_session(id) ON DELETE SET NULL,
  registro_huella CHAR(64) NOT NULL,
  estado VARCHAR(24) NOT NULL DEFAULT 'PENDIENTE',
  intentos SMALLINT NOT NULL DEFAULT 0 CHECK (intentos BETWEEN 0 AND 3),
  proximo_intento_en TIMESTAMP DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
  iniciado_en TIMESTAMP,
  ultimo_error VARCHAR(80),
  fcm_message_id VARCHAR(512),
  aceptado_en TIMESTAMP,
  recibido_en TIMESTAMP,
  CONSTRAINT uq_notificacion_entrega_registro UNIQUE (fk_notificacion, registro_huella),
  CONSTRAINT chk_notificacion_entrega_estado CHECK (estado IN (
    'PENDIENTE', 'EN_PROCESO', 'REINTENTO', 'ACEPTADA_FCM',
    'FALLIDA_PERMANENTE', 'OMITIDA', 'INDETERMINADA'
  )),
  CONSTRAINT chk_notificacion_entrega_huella CHECK (registro_huella ~ '^[0-9a-f]{64}$')
);

CREATE INDEX idx_notificacion_entrega_pendiente
  ON public.notificacion_entrega (proximo_intento_en, id)
  WHERE estado IN ('PENDIENTE', 'REINTENTO');

COMMENT ON COLUMN public.notificacion_entrega.registro_huella IS
  'SHA-256 of the FID; the complete identifier remains only in device_session.';
COMMENT ON COLUMN public.notificacion_entrega.aceptado_en IS
  'FCM acceptance only. This does not confirm receipt or display on Android.';
COMMENT ON COLUMN public.notificacion_entrega.recibido_en IS
  'Reserved for a future authenticated receipt acknowledgement; currently left NULL.';

COMMIT;
