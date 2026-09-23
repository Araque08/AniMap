const test = require('node:test');
const assert = require('node:assert/strict');
const postgres = require('../src/config/postgres_db');

const integrationTest =
  process.env.ANIMAP_RUN_MAP_WINDOW_INTEGRATION === '1' ? test : test.skip;

integrationTest(
  'PostgreSQL incluye exactamente 30 días y compara cerrado_en como UTC sin zona',
  async () => {
    const result = await postgres.query(`
      WITH clock AS (
        SELECT CURRENT_TIMESTAMP AT TIME ZONE 'UTC' AS now_utc
      ), samples(label, cerrado_en) AS (
        SELECT 'today', now_utc FROM clock
        UNION ALL SELECT 'day_29', now_utc - INTERVAL '29 days' FROM clock
        UNION ALL SELECT 'day_30', now_utc - INTERVAL '30 days' FROM clock
        UNION ALL SELECT 'older', now_utc - INTERVAL '30 days 1 microsecond' FROM clock
      )
      SELECT
        label,
        cerrado_en >=
          (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '30 days' AS visible,
        pg_typeof(cerrado_en)::text AS timestamp_type
      FROM samples
      ORDER BY label
    `);

    const byLabel = Object.fromEntries(
      result.rows.map((row) => [row.label, row])
    );
    assert.equal(byLabel.today.visible, true);
    assert.equal(byLabel.day_29.visible, true);
    assert.equal(byLabel.day_30.visible, true);
    assert.equal(byLabel.older.visible, false);
    assert.ok(
      result.rows.every(
        (row) => row.timestamp_type === 'timestamp without time zone'
      )
    );

    const schema = await postgres.query(`
      SELECT data_type
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'reporte'
        AND column_name = 'cerrado_en'
    `);
    assert.equal(schema.rows[0]?.data_type, 'timestamp without time zone');
  }
);
