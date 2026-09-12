const { reportsService } = require('./reports.service');

function parsePositiveId(value) {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : null;
}

async function listReportablePets(req, res, next) {
  try {
    const pets = await reportsService.listReportablePets(req.auth.userId);
    return res.status(200).json({ ok: true, total: pets.length, pets });
  } catch (error) {
    return next(error);
  }
}

async function listOwnReports(req, res, next) {
  try {
    const reports = await reportsService.listOwnReports(req.auth.userId);
    return res.status(200).json({ ok: true, total: reports.length, reports });
  } catch (error) {
    return next(error);
  }
}

async function getOwnReport(req, res, next) {
  const reportId = parsePositiveId(req.params.id);
  if (!reportId) {
    return res.status(400).json({ ok: false, message: 'ID de reporte inválido' });
  }
  try {
    const report = await reportsService.getOwnReport(req.auth.userId, reportId);
    return res.status(200).json({ ok: true, report });
  } catch (error) {
    return next(error);
  }
}

async function createReport(req, res, next) {
  try {
    const report = await reportsService.createReport(
      req.auth.userId,
      req.validatedBody
    );
    return res.status(201).json({
      ok: true,
      message: 'Reporte de pérdida creado correctamente',
      report,
    });
  } catch (error) {
    return next(error);
  }
}

async function updateReport(req, res, next) {
  const reportId = parsePositiveId(req.params.id);
  if (!reportId) {
    return res.status(400).json({ ok: false, message: 'ID de reporte inválido' });
  }
  try {
    const report = await reportsService.updateReport(
      req.auth.userId,
      reportId,
      req.validatedBody
    );
    return res.status(200).json({
      ok: true,
      message: 'Reporte actualizado correctamente',
      report,
    });
  } catch (error) {
    return next(error);
  }
}

async function closeReport(req, res, next) {
  const reportId = parsePositiveId(req.params.id);
  if (!reportId) {
    return res.status(400).json({ ok: false, message: 'ID de reporte inválido' });
  }
  try {
    const report = await reportsService.closeReport(req.auth.userId, reportId);
    return res.status(200).json({
      ok: true,
      message: 'Reporte finalizado correctamente',
      report,
    });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  closeReport,
  createReport,
  getOwnReport,
  listOwnReports,
  listReportablePets,
  updateReport,
};
