const env = require('../../config/env');

// Backend-only snapshot. Never derive QA scope from a request or Flutter input.
function createRecognitionQaScope({
  mode = process.env.RECOGNITION_QA_MODE ?? 'false', testMode = env.FCM_TEST_MODE,
  ownerId = env.FCM_TEST_OWNER_ID, reportId = env.FCM_TEST_REPORT_ID,
  reporterId = process.env.RECOGNITION_QA_REPORTER_ID,
} = {}) {
  const enabled = mode !== false && mode !== 'false';
  const positiveId = value => /^[1-9]\d*$/.test(String(value))
    && Number.isSafeInteger(Number(value)) && Number(value) <= 2147483647;
  const configured = !enabled || ((mode === true || mode === 'true')
    && (testMode === true || testMode === 'true')
    && positiveId(ownerId) && positiveId(reportId) && positiveId(reporterId)
    && Number(ownerId) !== Number(reporterId));
  const owner = Number(ownerId), report = Number(reportId), reporter = Number(reporterId);
  const failure = code => Object.assign(new Error('Reconocimiento QA no disponible para esta configuración.'),
    { code, statusCode: 503 });
  function assertReady() {
    if (!configured) throw failure('RECOGNITION_QA_NOT_CONFIGURED');
  }
  function assertAuthor(userId) {
    assertReady();
    if (enabled && Number(userId) !== reporter) throw failure('RECOGNITION_QA_SCOPE_FORBIDDEN');
  }
  function allowsPhoto(photo) {
    assertReady();
    return !enabled || (photo?.ownerId === owner && photo?.reportId === report);
  }
  // Only internal aliases/parameter offsets enter these SQL fragments.
  function sightingFilter(alias, first) {
    assertReady();
    if (!enabled) return { text: '', values: [] };
    return { text: `AND ${alias}.fk_usuario=$${first}
      AND ${alias}.estado IS DISTINCT FROM 'ELIMINADO'
      AND (${alias}.fk_reporte_perdida IS NULL OR ${alias}.fk_reporte_perdida=$${first + 1})
      AND EXISTS (SELECT 1 FROM reporte qa_r JOIN mascota qa_m
        ON qa_m.id=qa_r.fk_mascota AND qa_m.fk_usuario=qa_r.fk_usuario
        WHERE qa_r.id=$${first + 1} AND qa_r.fk_usuario=$${first + 2}
          AND qa_r.estado='ACTIVO' AND qa_m.estado='PERDIDA')`,
    values: [reporter, report, owner] };
  }
  function jobFilter(alias, first) {
    const filter = sightingFilter('qa_a', first);
    if (!enabled) return filter;
    return { text: `AND ${alias}.fk_usuario=$${first}
      AND EXISTS (SELECT 1 FROM avistamiento qa_a
        WHERE qa_a.id=${alias}.fk_avistamiento AND qa_a.fk_usuario=${alias}.fk_usuario ${filter.text})`,
    values: filter.values };
  }
  return Object.freeze({ enabled, ownerId: owner, reportId: report,
    assertReady, assertAuthor, allowsPhoto, sightingFilter, jobFilter });
}
module.exports = { createRecognitionQaScope };