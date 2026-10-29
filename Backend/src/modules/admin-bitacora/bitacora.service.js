
const db = require('../../config/postgres_db');

/*
  Consulta los registros de la bitácora administrativa.
  No permite modificar ni eliminar registros.
*/
async function listarBitacora({
  modulo,
  accion,
  desde,
  hasta,
  pagina = 1,
  limite = 20,
}) {
  const condiciones = [];
  const parametros = [];

  function agregarCondicion(valor, expresion) {
    parametros.push(valor);
    condiciones.push(
      expresion.replace('?', `$${parametros.length}`)
    );
  }

  if (modulo) {
    agregarCondicion(
      `%${modulo}%`,
      'b.modulo ILIKE ?'
    );
  }

  if (accion) {
    agregarCondicion(
      `%${accion}%`,
      'b.accion ILIKE ?'
    );
  }

  if (desde) {
    agregarCondicion(
      desde,
      'b.fecha_hora >= ?::date'
    );
  }

  if (hasta) {
    agregarCondicion(
      hasta,
      "b.fecha_hora < (?::date + INTERVAL '1 day')"
    );
  }

  const where = condiciones.length
    ? `WHERE ${condiciones.join(' AND ')}`
    : '';

  const consultaTotal = await db.query(
    `
      SELECT COUNT(*)::int AS total
      FROM bitacora_administrativa b
      ${where}
    `,
    parametros
  );

  const total = consultaTotal.rows[0].total;
  const offset = (pagina - 1) * limite;

  const valoresConsulta = [
    ...parametros,
    limite,
    offset,
  ];

  const parametroLimite = `$${parametros.length + 1}`;
  const parametroOffset = `$${parametros.length + 2}`;

  const resultado = await db.query(
    `
      SELECT
        b.id,
        b.fk_admin,
        u.email AS administrador,
        b.modulo,
        b.accion,
        b.entidad_afectada,
        b.id_entidad_afectada,
        b.motivo,
        b.detalle,
        b.fecha_hora

      FROM bitacora_administrativa b

      INNER JOIN usuario u
        ON u.id = b.fk_admin

      ${where}

      ORDER BY b.fecha_hora DESC, b.id DESC

      LIMIT ${parametroLimite}
      OFFSET ${parametroOffset}
    `,
    valoresConsulta
  );

  return {
    registros: resultado.rows,
    paginacion: {
      pagina,
      limite,
      total,
      totalPaginas: Math.ceil(total / limite),
    },
  };
}

module.exports = {
  listarBitacora,
};
