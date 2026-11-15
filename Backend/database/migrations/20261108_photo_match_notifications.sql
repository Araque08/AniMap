-- HU034 / ANIMAP-80. Review and apply separately; the application never runs this file.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- Existing evidence must survive removal of a reference photograph. Keep every
-- existing row, make that one relation optional, and replace its cascading FK.
ALTER TABLE public.coincidencia_reconocimiento ALTER COLUMN fk_foto_mascota DROP NOT NULL;
DO $$
DECLARE relation RECORD;
BEGIN
  FOR relation IN SELECT c.conname FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid='public.coincidencia_reconocimiento'::regclass
      AND c.contype='f' AND a.attname='fk_foto_mascota'
  LOOP
    EXECUTE format('ALTER TABLE public.coincidencia_reconocimiento DROP CONSTRAINT %I', relation.conname);
  END LOOP;
END $$;
ALTER TABLE public.coincidencia_reconocimiento ADD CONSTRAINT fk_coincidencia_foto_mascota
  FOREIGN KEY (fk_foto_mascota) REFERENCES public.foto_mascota(id) ON DELETE SET NULL;

-- Nullable additions preserve historical evidence whose original recipient was
-- not recorded. New owner-scoped events always populate report and recipient.
ALTER TABLE public.coincidencia_reconocimiento
  ADD COLUMN IF NOT EXISTS fk_reporte INTEGER REFERENCES public.reporte(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS fk_usuario INTEGER REFERENCES public.usuario(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS fk_notificacion INTEGER REFERENCES public.notificacion(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS modelo VARCHAR(120);
CREATE UNIQUE INDEX IF NOT EXISTS uq_coincidencia_foto_reporte_destinatario
  ON public.coincidencia_reconocimiento(fk_foto_avistamiento, fk_reporte, fk_usuario)
  WHERE fk_usuario IS NOT NULL AND fk_reporte IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_coincidencia_notificacion
  ON public.coincidencia_reconocimiento(fk_notificacion) WHERE fk_notificacion IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_coincidencia_propietario_historial
  ON public.coincidencia_reconocimiento(fk_usuario, id DESC) WHERE fk_usuario IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.reconocimiento_publicacion (
  fk_avistamiento INTEGER PRIMARY KEY REFERENCES public.avistamiento(id) ON DELETE CASCADE,
  fk_usuario INTEGER NOT NULL REFERENCES public.usuario(id) ON DELETE CASCADE,
  solicitud_id UUID NOT NULL,
  huella CHAR(64) NOT NULL CHECK(huella ~ '^[0-9a-f]{64}$'),
  compartir_contacto BOOLEAN NOT NULL DEFAULT FALSE,
  estado VARCHAR(16) NOT NULL DEFAULT 'PENDIENTE'
    CHECK(estado IN ('PENDIENTE','EN_PROCESO','REINTENTO','COMPLETADA','FALLIDA')),
  intentos SMALLINT NOT NULL DEFAULT 0 CHECK(intentos BETWEEN 0 AND 3),
  proximo_intento_en TIMESTAMP DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
  reclamo_id UUID,
  reclamado_en TIMESTAMP,
  ultimo_error VARCHAR(80),
  creado_en TIMESTAMP NOT NULL DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
  CONSTRAINT uq_reconocimiento_publicacion_autor_solicitud UNIQUE(fk_usuario,solicitud_id)
);
CREATE INDEX IF NOT EXISTS idx_reconocimiento_publicacion_pendiente
  ON public.reconocimiento_publicacion(proximo_intento_en,fk_avistamiento)
  WHERE estado IN ('PENDIENTE','REINTENTO','EN_PROCESO');
COMMENT ON TABLE public.reconocimiento_publicacion IS
  'Durable photo analysis jobs. At most three analyses; expired third claims are finalized without another analysis.';
COMMENT ON COLUMN public.coincidencia_reconocimiento.fk_foto_avistamiento IS
  'Original sighting photo metadata; binary content remains in ImagenAvistamiento, never duplicated here.';
COMMENT ON COLUMN public.coincidencia_reconocimiento.fk_foto_mascota IS
  'Optional reference after photo deletion; ON DELETE SET NULL preserves legacy and owner-scoped evidence.';
COMMIT;
