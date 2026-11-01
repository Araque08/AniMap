-- Define en repositorios nuevos la tabla ya existente en la BD compartida.
-- Revisar y aplicar por separado. El servidor no ejecuta esta migración.
BEGIN;

CREATE TABLE IF NOT EXISTS public.revision_duplicados (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tipo VARCHAR(20) NOT NULL,
  registro_1_id BIGINT NOT NULL,
  registro_2_id BIGINT NOT NULL,
  registro_conservado_id BIGINT,
  registro_eliminado_id BIGINT,
  estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
  motivo TEXT,
  fk_admin BIGINT REFERENCES public.usuario(id),
  fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_revision TIMESTAMP,
  notificacion_enviada BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT uq_revision_duplicados UNIQUE (tipo, registro_1_id, registro_2_id),
  CONSTRAINT chk_tipo_duplicado CHECK (tipo IN ('REPORTE', 'AVISTAMIENTO')),
  CONSTRAINT chk_orden_registros CHECK (registro_1_id < registro_2_id),
  CONSTRAINT chk_estado_revision CHECK (estado IN ('PENDIENTE', 'CONFIRMADO', 'DESCARTADO')),
  CONSTRAINT chk_decision_duplicado CHECK (
    (estado = 'CONFIRMADO' AND registro_conservado_id IS NOT NULL
      AND registro_eliminado_id IS NOT NULL AND registro_conservado_id <> registro_eliminado_id
      AND registro_conservado_id IN (registro_1_id, registro_2_id)
      AND registro_eliminado_id IN (registro_1_id, registro_2_id)
      AND fk_admin IS NOT NULL AND fecha_revision IS NOT NULL)
    OR (estado <> 'CONFIRMADO' AND registro_conservado_id IS NULL AND registro_eliminado_id IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_revision_duplicados_estado ON public.revision_duplicados (estado);
-- Los IDs son polimórficos (REPORTE/AVISTAMIENTO); el servicio comprueba y
-- bloquea los avistamientos dentro de la transacción antes de confirmar.
-- notificacion_enviada indica que se creó la notificación interna, no entrega FCM.
COMMIT;