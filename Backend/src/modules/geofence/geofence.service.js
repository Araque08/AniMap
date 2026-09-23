const fs = require('fs');
const path = require('path');

const OUTSIDE_ALLOWED_AREA_MESSAGE =
  'Esta ubicación está fuera de Ciudad Salitre Occidental. AniMap actualmente ' +
  'permite registrar pérdidas y avistamientos únicamente dentro de la zona piloto.';

const geojsonPath = path.join(
  __dirname,
  '../../data/geofences/salitre_occidental_006313.geojson'
);

function normalizeName(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .replace(/\s+/g, ' ')
    .toUpperCase();
}

function loadOfficialFeature(filePath = geojsonPath) {
  const document = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (document.type !== 'FeatureCollection' || document.features?.length !== 1) {
    throw new Error('El GeoJSON oficial debe contener exactamente un feature');
  }
  const feature = document.features[0];
  const properties = feature.properties || {};
  if (properties.SCACODIGO !== '006313') {
    throw new Error('El código del geofence oficial no es 006313');
  }
  if (normalizeName(properties.SCANOMBRE) !== 'SALITRE OCCIDENTAL') {
    throw new Error('El nombre del geofence oficial no es SALITRE OCCIDENTAL');
  }
  if (properties.SCATIPO !== 0) {
    throw new Error('El geofence oficial no corresponde a un sector URBANO');
  }
  if (!['Polygon', 'MultiPolygon'].includes(feature.geometry?.type)) {
    throw new Error('La geometría oficial debe ser Polygon o MultiPolygon');
  }
  return feature;
}

const officialFeature = loadOfficialFeature();

function assertCoordinates(lat, lng) {
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
    const error = new Error('La latitud debe estar entre -90 y 90');
    error.statusCode = 400;
    error.code = 'INVALID_COORDINATES';
    throw error;
  }
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
    const error = new Error('La longitud debe estar entre -180 y 180');
    error.statusCode = 400;
    error.code = 'INVALID_COORDINATES';
    throw error;
  }
}

function pointOnSegment(point, start, end) {
  const [x, y] = point;
  const [x1, y1] = start;
  const [x2, y2] = end;
  const cross = (x - x1) * (y2 - y1) - (y - y1) * (x2 - x1);
  const scale = Math.max(1, Math.abs(x2 - x1), Math.abs(y2 - y1));
  if (Math.abs(cross) > 1e-12 * scale) return false;
  return (
    x >= Math.min(x1, x2) - 1e-12 &&
    x <= Math.max(x1, x2) + 1e-12 &&
    y >= Math.min(y1, y2) - 1e-12 &&
    y <= Math.max(y1, y2) + 1e-12
  );
}

function ringContains(point, ring) {
  let inside = false;
  for (let index = 0, previous = ring.length - 1; index < ring.length; previous = index++) {
    const currentPoint = ring[index];
    const previousPoint = ring[previous];
    if (pointOnSegment(point, previousPoint, currentPoint)) {
      return { inside: true, boundary: true };
    }
    const crosses =
      currentPoint[1] > point[1] !== previousPoint[1] > point[1] &&
      point[0] <
        ((previousPoint[0] - currentPoint[0]) *
          (point[1] - currentPoint[1])) /
          (previousPoint[1] - currentPoint[1]) +
          currentPoint[0];
    if (crosses) inside = !inside;
  }
  return { inside, boundary: false };
}

function polygonContains(point, polygon) {
  for (const ring of polygon) {
    if (ringContains(point, ring).boundary) return true;
  }
  if (!ringContains(point, polygon[0]).inside) return false;
  return !polygon.slice(1).some((hole) => ringContains(point, hole).inside);
}

function geometryContains(geometry, point) {
  const polygons = geometry.type === 'Polygon'
    ? [geometry.coordinates]
    : geometry.coordinates;
  return polygons.some((polygon) => polygonContains(point, polygon));
}

function isInsideAllowedArea(lat, lng) {
  assertCoordinates(lat, lng);
  return geometryContains(officialFeature.geometry, [lng, lat]);
}

function resolveGeofenceMode(value = process.env.GEOFENCE_MODE) {
  return value === 'WARN' || value === 'ENFORCE' ? value : 'ENFORCE';
}

function evaluateAllowedArea(lat, lng, modeValue) {
  const inside = isInsideAllowedArea(lat, lng);
  const mode = resolveGeofenceMode(modeValue);
  return {
    inside,
    allowed: inside || mode === 'WARN',
    mode,
    area,
  };
}

function validateAllowedArea(lat, lng, modeValue) {
  const result = evaluateAllowedArea(lat, lng, modeValue);
  if (!result.allowed) {
    const error = new Error(OUTSIDE_ALLOWED_AREA_MESSAGE);
    error.statusCode = 422;
    error.code = 'OUTSIDE_ALLOWED_AREA';
    throw error;
  }
  return result;
}

const area = Object.freeze({ code: '006313', name: 'Salitre Occidental' });

module.exports = {
  OUTSIDE_ALLOWED_AREA_MESSAGE,
  area,
  evaluateAllowedArea,
  geometryContains,
  isInsideAllowedArea,
  loadOfficialFeature,
  officialFeature,
  pointOnSegment,
  resolveGeofenceMode,
  validateAllowedArea,
};
