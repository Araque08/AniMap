
const bitacoraService = require('./bitacora.service');

function fechaValida(valor) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(valor)) {
    return false;
  }

  const fecha = new Date(`${valor}T00:00:00Z`);

  return (
    !Number.isNaN(fecha.getTime()) &&
    fecha.toISOString().slice(0, 10) === valor
  );
}

async function listarBitacora(req, res) {
  try {
    const {
      modulo,
      accion,
      desde,
      hasta,
    } = req.query;

    const pagina = Number(req.query.pagina ?? 1);
    const limite = Number(req.query.limite ?? 20);

    if (
      !Number.isSafeInteger(pagina) ||
      pagina < 1 ||
      !Number.isSafeInteger(limite) ||
      limite < 1 ||
      limite > 100
    ) {
      return res.status(400).json({
        ok: false,
        message: 'Paginación inválida',
      });
    }

    for (const campo of [modulo, accion, desde, hasta]) {
      if (
        campo !== undefined &&
        (typeof campo !== 'string' || campo.length > 100)
      ) {
        return res.status(400).json({
          ok: false,
          message: 'Filtros inválidos',
        });
      }
    }

    if (
      (desde && !fechaValida(desde)) ||
      (hasta && !fechaValida(hasta))
    ) {
      return res.status(400).json({
        ok: false,
        message: 'Formato de fecha inválido. Use YYYY-MM-DD',
      });
    }

    if (desde && hasta && desde > hasta) {
      return res.status(400).json({
        ok: false,
        message: 'La fecha inicial supera la fecha final',
      });
    }

    const resultado = await bitacoraService.listarBitacora({
      modulo: modulo?.trim(),
      accion: accion?.trim(),
      desde,
      hasta,
      pagina,
      limite,
    });

    return res.status(200).json({
      ok: true,
      message: 'Bitácora consultada correctamente',
      data: resultado.registros,
      paginacion: resultado.paginacion,
    });
  } catch (error) {
    console.error('Error al consultar bitácora:', error);

    return res.status(500).json({
      ok: false,
      message: 'No fue posible consultar la bitácora',
    });
  }
}

module.exports = {
  listarBitacora,
};
