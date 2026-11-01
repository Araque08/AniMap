-- ANIMAP-35. Apply separately after review; no real credentials belong here.
-- Flutter Messaging 17 uses FIDs through register()/onRegistered.
BEGIN;

ALTER TABLE public.device_session
  ADD COLUMN IF NOT EXISTS fcm_registration_id VARCHAR(255),
  ADD COLUMN IF NOT EXISTS fcm_registration_updated_at TIMESTAMP;

CREATE UNIQUE INDEX IF NOT EXISTS uq_device_session_fcm_registration
  ON public.device_session (fcm_registration_id)
  WHERE fcm_registration_id IS NOT NULL;

COMMENT ON COLUMN public.device_session.fcm_registration_id IS
  'FCM installation ID (FID). Usable only while this session is active and unexpired; never expose in session listings.';

COMMIT;
