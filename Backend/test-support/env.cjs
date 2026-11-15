
process.env.NODE_ENV = 'test';

// Evitar envíos reales durante las pruebas.
process.env.FCM_PUSH_ENABLED = 'false';

// Configuración controlada de las pruebas Firebase.
process.env.FCM_TEST_MODE = 'false';
process.env.FCM_TEST_OWNER_ID = '';
process.env.FCM_TEST_REPORT_ID = '';

// Las pruebas de RF-0068 requieren bloquear
// ubicaciones exteriores por defecto.
process.env.GEOFENCE_MODE = 'ENFORCE';

// Credenciales exclusivas para las pruebas.
process.env.JWT_ACCESS_SECRET = 'animap-test-access-secret';
process.env.JWT_REFRESH_SECRET = 'animap-test-refresh-secret';

process.env.ADMIN_FCM_ENABLED = 'false';
process.env.ADMIN_FCM_GENERAL_ENABLED = 'false';

process.env.PHOTO_MATCH_ENABLED = 'false';
process.env.COMMUNITY_ALERTS_ENABLED = 'false';

// El aislamiento QA se activa explicitamente por fixture, nunca por el entorno del desarrollador.
process.env.RECOGNITION_QA_MODE = 'false';
process.env.RECOGNITION_QA_REPORTER_ID = '';
