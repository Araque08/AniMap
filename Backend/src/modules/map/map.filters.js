const { z } = require('zod');

const calendarDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
});
const attribute = z.string().trim().min(1).max(100).transform(value => value.toLowerCase());
const mapFiltersSchema = z.object({
  species: attribute.optional(),
  color: attribute.optional(),
  from: calendarDate.optional(),
  to: calendarDate.optional(),
  status: z.enum(['active', 'found']).optional(),
}).refine(value => !value.from || !value.to || value.from <= value.to);

// Column expressions are chosen here, never supplied by the client.
function mapFilterSql(filters, sighting = false) {
  const clauses = [];
  const values = [];
  const parameter = value => { values.push(value); return `$${values.length}`; };
  if (filters.species) clauses.push(`LOWER(BTRIM(e.nombre)) = ${parameter(filters.species)}`);
  if (filters.color) clauses.push(`LOWER(BTRIM(m.color)) = ${parameter(filters.color)}`);
  const date = sighting ? 'a.fecha_hora'
    : "(CASE WHEN r.estado = 'FINALIZADO' THEN r.cerrado_en ELSE r.creado_en END)";
  if (filters.from) clauses.push(`${date} >= (${parameter(filters.from)}::date::timestamp AT TIME ZONE 'America/Bogota' AT TIME ZONE 'UTC')`);
  if (filters.to) clauses.push(`${date} < ((${parameter(filters.to)}::date + INTERVAL '1 day') AT TIME ZONE 'America/Bogota' AT TIME ZONE 'UTC')`);
  if (!sighting && filters.status) clauses.push(`r.estado = '${filters.status === 'found' ? 'FINALIZADO' : 'ACTIVO'}'`);
  return { sql: clauses.length ? ` AND ${clauses.join(' AND ')}` : '', values };
}

module.exports = { mapFiltersSchema, mapFilterSql };
