-- Apply separately with push disabled and all backends upgraded. Never run at startup.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TABLE public.device_push_registration (
  id BIGSERIAL PRIMARY KEY,
  fk_usuario INTEGER NOT NULL REFERENCES public.usuario(id),
  device_id VARCHAR(120) NOT NULL,
  fk_device_session INTEGER REFERENCES public.device_session(id) ON DELETE SET NULL,
  fcm_registration_id VARCHAR(255) UNIQUE,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en TIMESTAMP NOT NULL DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
  actualizado_en TIMESTAMP NOT NULL DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
  revocado_en TIMESTAMP,
  CONSTRAINT uq_push_usuario_dispositivo UNIQUE (fk_usuario, device_id),
  CONSTRAINT chk_push_activo CHECK (NOT activo OR
    (fcm_registration_id IS NOT NULL AND btrim(fcm_registration_id) <> ''))
);

-- Only live authenticated associations are eligible for the initial transfer.
-- Historical expired/revoked sessions are not promoted to push registrations.
INSERT INTO public.device_push_registration
  (fk_usuario, device_id, fk_device_session, fcm_registration_id, actualizado_en)
SELECT DISTINCT ON (ds.fk_usuario, ds.device_id)
  ds.fk_usuario, ds.device_id, ds.id, ds.fcm_registration_id,
  COALESCE(ds.fcm_registration_updated_at, CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
FROM public.device_session ds JOIN public.usuario u ON u.id = ds.fk_usuario
WHERE ds.vigente = TRUE AND ds.expira_en > LOCALTIMESTAMP
  AND ds.fcm_registration_id IS NOT NULL AND btrim(ds.fcm_registration_id) <> ''
  AND u.estado_cuenta = 'ACTIVO' AND u.is_verified = TRUE
ORDER BY ds.fk_usuario, ds.device_id, ds.id DESC;

ALTER TABLE public.notificacion_entrega ADD COLUMN fk_push_registration BIGINT
  REFERENCES public.device_push_registration(id) ON DELETE SET NULL;
-- Preserve pending delivery identity/fingerprint; never revive accepted sends.
UPDATE public.notificacion_entrega d SET fk_push_registration = p.id
FROM public.device_push_registration p
WHERE d.fk_device_session = p.fk_device_session
  AND d.registro_huella = encode(sha256(convert_to(p.fcm_registration_id, 'UTF8')), 'hex');

COMMENT ON TABLE public.device_push_registration IS
  'Push consent survives API inactivity; explicit logout, revocation or account switch removes it.';
COMMENT ON COLUMN public.notificacion_entrega.registro_huella IS
  'SHA-256 of the registration identifier; full identifier is stored in device_push_registration (legacy session mirror retained).';
COMMIT;
