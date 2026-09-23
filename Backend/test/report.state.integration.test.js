const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

const db = require('../src/config/postgres_db');
const { hashText } = require('../src/utils/hash');
const { reportsService } = require('../src/modules/reports/reports.service');

const integrationTest =
  process.env.ANIMAP_RUN_REPORT_STATE_INTEGRATION === '1' ? test : test.skip;

integrationTest(
  'ciclo real ACTIVA a PERDIDA a ACTIVA conserva el reporte FINALIZADO',
  async () => {
    const suffix = randomUUID();
    const email = `report-state-${suffix}@example.invalid`;
    const passwordHash = await hashText(`Report-${suffix.slice(0, 8)}-A1!`);
    let userId;
    let petId;
    let reportId;

    try {
      const species = await db.pool.query(
        'SELECT id FROM especie ORDER BY id LIMIT 1',
      );
      assert.equal(species.rowCount, 1);

      const user = await db.pool.query(
        `INSERT INTO usuario
           (nombre, email, telefono, password_hash, is_verified, acepta_tyc, estado_cuenta)
         VALUES ($1, $2, $3, $4, TRUE, TRUE, 'ACTIVO')
         RETURNING id`,
        ['Report State E2E', email, '3000000000', passwordHash],
      );
      userId = user.rows[0].id;

      const pet = await db.pool.query(
        `INSERT INTO mascota
           (fk_usuario, fk_especie, nombre, color, sexo, estado)
         VALUES ($1, $2, $3, $4, 'NO_DEFINIDO', 'ACTIVA')
         RETURNING id`,
        [userId, species.rows[0].id, 'Pet Report State E2E', 'Café'],
      );
      petId = pet.rows[0].id;

      const created = await reportsService.createReport(userId, {
        mascotaId: petId,
        descripcion: 'Reporte temporal para validar estado',
        mostrarContacto: false,
        ubicacion: {
          metodo: 'MAPA',
          lat: 4.651,
          lng: -74.109,
          precisionM: null,
          direccion: 'Referencia temporal',
          placeId: null,
        },
      });
      reportId = created.id;

      const lost = await db.pool.query(
        'SELECT estado FROM mascota WHERE id = $1 AND fk_usuario = $2',
        [petId, userId],
      );
      assert.equal(lost.rows[0].estado, 'PERDIDA');

      await reportsService.closeReport(userId, reportId);
      const finalState = await db.pool.query(
        `SELECT r.estado AS reporte_estado, r.cerrado_en,
                m.estado AS mascota_estado
         FROM reporte r
         INNER JOIN mascota m ON m.id = r.fk_mascota
         WHERE r.id = $1 AND r.fk_usuario = $2`,
        [reportId, userId],
      );
      assert.equal(finalState.rows[0].reporte_estado, 'FINALIZADO');
      assert.ok(finalState.rows[0].cerrado_en);
      assert.equal(finalState.rows[0].mascota_estado, 'ACTIVA');
    } finally {
      if (userId) {
        const client = await db.pool.connect();
        try {
          await client.query('BEGIN');
          if (reportId) {
            await client.query('DELETE FROM ubicacion WHERE fk_reporte = $1', [
              reportId,
            ]);
            await client.query(
              'DELETE FROM reporte WHERE id = $1 AND fk_usuario = $2',
              [reportId, userId],
            );
          }
          if (petId) {
            await client.query(
              'DELETE FROM mascota WHERE id = $1 AND fk_usuario = $2',
              [petId, userId],
            );
          }
          await client.query(
            'DELETE FROM usuario WHERE id = $1 AND email = $2',
            [userId, email],
          );
          await client.query('COMMIT');
        } catch (error) {
          await client.query('ROLLBACK').catch(() => undefined);
          throw error;
        } finally {
          client.release();
        }

        const residue = await db.pool.query(
          `SELECT
             (SELECT COUNT(*)::int FROM usuario WHERE id = $1) AS usuario,
             (SELECT COUNT(*)::int FROM mascota WHERE id = $2) AS mascota,
             (SELECT COUNT(*)::int FROM reporte WHERE id = $3) AS reporte,
             (SELECT COUNT(*)::int FROM ubicacion WHERE fk_reporte = $3) AS ubicacion`,
          [userId, petId || 0, reportId || 0],
        );
        assert.deepEqual(residue.rows[0], {
          usuario: 0,
          mascota: 0,
          reporte: 0,
          ubicacion: 0,
        });
      }
    }
  },
);
