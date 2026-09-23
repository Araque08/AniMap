const { sightingsService } = require('./sightings.service');
const { historyPeriodSchema } = require('./sightings.schemas');

function positiveId(value) {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : null;
}

async function createSighting(req, res, next) {
  try {
    const sighting = await sightingsService.createSighting(
      req.auth.userId,
      req.validatedBody,
      req.file || null
    );
    return res.status(201).json({
      ok: true,
      message: 'Avistamiento registrado correctamente',
      sighting,
    });
  } catch (error) {
    return next(error);
  }
}

async function getPublicSighting(req, res, next) {
  const sightingId = positiveId(req.params.id);
  if (!sightingId) {
    return res.status(400).json({ ok: false, message: 'ID de avistamiento inválido' });
  }
  try {
    const sighting = await sightingsService.getPublicSighting(sightingId);
    return res.status(200).json({ ok: true, sighting });
  } catch (error) {
    return next(error);
  }
}

async function listLinkableReports(req, res, next) {
  try {
    const reports = await sightingsService.listLinkableReports();
    return res.status(200).json({ ok: true, total: reports.length, reports });
  } catch (error) {
    return next(error);
  }
}

async function getPublicImage(req, res, next) {
  try {
    const image = await sightingsService.getPublicImage(req.params.imageId);
    res.set('Content-Type', image.mimeType);
    res.set('Cache-Control', 'public, max-age=3600');
    return res.send(image.buffer);
  } catch (error) {
    return next(error);
  }
}

async function getReportHistory(req, res, next) {
  const reportId = positiveId(req.params.reportId);
  if (!reportId) {
    return res.status(400).json({ ok: false, message: 'ID de reporte inválido' });
  }

  const periodResult = historyPeriodSchema.safeParse(req.query.period || 'ALL');
  if (!periodResult.success) {
    return res.status(400).json({
      ok: false,
      message: 'Período inválido. Use ALL, TODAY, 7D o 30D',
    });
  }

  try {
    const history = await sightingsService.getReportHistory(
      req.auth.userId,
      reportId,
      periodResult.data
    );
    return res.status(200).json({ ok: true, ...history });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  createSighting,
  getPublicImage,
  getPublicSighting,
  getReportHistory,
  listLinkableReports,
};
