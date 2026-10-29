
const {
  adminReportsService,
} = require('./admin-reports.service');

// ==========================================================
// LISTAR Y BUSCAR REPORTES
// ==========================================================

async function listReports(req, res, next) {
  try {
    const reports = await adminReportsService.listReports({
      search: req.query.search,
      estado: req.query.estado,
    });

    return res.status(200).json({
      ok: true,
      total: reports.length,
      reports,
    });
  } catch (error) {
    return next(error);
  }
}

// ==========================================================
// OBTENER DETALLE DE UN REPORTE
// ==========================================================

async function getReport(req, res, next) {
  try {
    const report = await adminReportsService.getReportById(
      req.params.id
    );

    return res.status(200).json({
      ok: true,
      report,
    });
  } catch (error) {
    return next(error);
  }
}


/*
  ============================================================
  HU-076: MODIFICAR ESTADO DE REPORTE Y MASCOTA
  ============================================================
*/

async function updateReportStatus(req, res, next) {
  try {
    const reportId = Number(req.params.id);

    if (!Number.isInteger(reportId) || reportId <= 0) {
      return res.status(400).json({
        ok: false,
        message: 'ID de reporte inválido',
      });
    }

    const { estadoReporte, estadoMascota } = req.body;

    if (
      typeof estadoReporte !== 'string' ||
      typeof estadoMascota !== 'string'
    ) {
      return res.status(400).json({
        ok: false,
        message:
          'Debes proporcionar el estado del reporte y de la mascota',
      });
    }

    const result = await adminReportsService.updateReportStatus(
      reportId,
      {
        estadoReporte,
        estadoMascota,
      },
      req.auth.userId
    );

    return res.status(200).json({
      ok: true,
      message: 'Estados actualizados correctamente',
      data: result,
    });

  } catch (error) {
    return next(error);
  }
}


// ==========================================================
// EXPORTAR CONTROLADORES
// ==========================================================

module.exports = {
  listReports,
  getReport,
  updateReportStatus,
};
