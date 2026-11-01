const db = require('../src/config/postgres_db');

// Explicit database fixtures for route tests; JWT verification and RBAC stay real.
function installAuthFixture(roles) {
  const original = db.query;
  db.query = async (sql, values) => {
    const userId = Number(values?.[0]);
    if (sql.includes('FROM device_session ds')) {
      return roles[userId]
        ? { rowCount: 1, rows: [{ session_id: userId, session_expired: false,
          email: 'fixture@example.invalid', is_verified: true, estado_cuenta: 'ACTIVO' }] }
        : { rowCount: 0, rows: [] };
    }
    if (sql.includes('FROM usuario_rol')) {
      return { rowCount: roles[userId] ? 1 : 0, rows: roles[userId] ? [{ nombre: roles[userId] }] : [] };
    }
    if (sql.includes('UPDATE device_session') && sql.includes('expira_en')) {
      return { rowCount: 1, rows: [{ id: userId }] };
    }
    return original(sql, values);
  };
  return () => { db.query = original; };
}
module.exports = { installAuthFixture };
