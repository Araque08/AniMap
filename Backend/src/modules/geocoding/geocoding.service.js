const geofence = require('../geofence/geofence.service');

const GOOGLE_GEOCODING_URL = 'https://maps.googleapis.com/maps/api/geocode/json';
const OFFICIAL_BOUNDS = Object.freeze({
  southwest: Object.freeze({ lat: 4.64515306200002, lng: -74.11464725999997 }),
  northeast: Object.freeze({ lat: 4.6581094910000616, lng: -74.10342315199995 }),
});

const messages = Object.freeze({
  ADDRESS_REQUIRED: 'La dirección es obligatoria.',
  ADDRESS_NOT_FOUND:
    'No encontramos esa dirección. Verifica los datos e inténtalo nuevamente.',
  ADDRESS_OUTSIDE_ALLOWED_AREA:
    'La dirección encontrada está fuera de Ciudad Salitre Occidental. AniMap actualmente permite registrar pérdidas y avistamientos únicamente dentro de la zona piloto.',
  GEOCODING_NOT_CONFIGURED:
    'El servicio de validación de direcciones no está configurado.',
  GEOCODING_UNAVAILABLE:
    'No pudimos validar la dirección en este momento. Inténtalo nuevamente.',
  INVALID_GEOCODING_RESPONSE:
    'El proveedor devolvió una respuesta de ubicación inválida.',
});

function httpError(code, statusCode) {
  const error = new Error(messages[code]);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}

function buildRequestUrl(address, apiKey) {
  const url = new URL(GOOGLE_GEOCODING_URL);
  url.searchParams.set('address', address);
  url.searchParams.set('components', 'country:CO');
  url.searchParams.set('region', 'co');
  url.searchParams.set('language', 'es');
  url.searchParams.set(
    'bounds',
    `${OFFICIAL_BOUNDS.southwest.lat},${OFFICIAL_BOUNDS.southwest.lng}|` +
      `${OFFICIAL_BOUNDS.northeast.lat},${OFFICIAL_BOUNDS.northeast.lng}`
  );
  url.searchParams.set('key', apiKey);
  return url;
}

function createGeocodingService({
  apiKey = process.env.GOOGLE_GEOCODING_API_KEY,
  fetchImpl = global.fetch,
  geofenceService = geofence,
  timeoutMs = 8000,
} = {}) {
  async function geocodeAddress(rawAddress) {
    const address = typeof rawAddress === 'string' ? rawAddress.trim() : '';
    if (!address) throw httpError('ADDRESS_REQUIRED', 400);
    if (!apiKey) throw httpError('GEOCODING_NOT_CONFIGURED', 503);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    let response;
    try {
      response = await fetchImpl(buildRequestUrl(address, apiKey), {
        method: 'GET',
        signal: controller.signal,
      });
    } catch (_) {
      throw httpError('GEOCODING_UNAVAILABLE', 503);
    } finally {
      clearTimeout(timeout);
    }

    if (!response?.ok) throw httpError('GEOCODING_UNAVAILABLE', 503);

    let body;
    try {
      body = await response.json();
    } catch (_) {
      throw httpError('INVALID_GEOCODING_RESPONSE', 502);
    }
    if (!body || typeof body !== 'object' || typeof body.status !== 'string') {
      throw httpError('INVALID_GEOCODING_RESPONSE', 502);
    }
    if (body.status === 'ZERO_RESULTS') {
      throw httpError('ADDRESS_NOT_FOUND', 404);
    }
    if (body.status !== 'OK') {
      throw httpError('GEOCODING_UNAVAILABLE', 503);
    }
    if (!Array.isArray(body.results)) {
      throw httpError('INVALID_GEOCODING_RESPONSE', 502);
    }

    const candidates = body.results.slice(0, 5).map((result) => {
      const formattedAddress = result?.formatted_address;
      const placeId = result?.place_id;
      const location = result?.geometry?.location;
      const locationType = result?.geometry?.location_type;
      const lat = location?.lat;
      const lng = location?.lng;
      if (
        typeof formattedAddress !== 'string' || !formattedAddress.trim() ||
        typeof placeId !== 'string' || !placeId.trim() ||
        typeof locationType !== 'string' || !locationType.trim() ||
        !Number.isFinite(lat) || lat < -90 || lat > 90 ||
        !Number.isFinite(lng) || lng < -180 || lng > 180
      ) {
        throw httpError('INVALID_GEOCODING_RESPONSE', 502);
      }
      const areaResult = geofenceService.evaluateAllowedArea(lat, lng);
      return {
        formattedAddress: formattedAddress.trim(),
        lat,
        lng,
        placeId: placeId.trim(),
        locationType: locationType.trim(),
        inside: areaResult.inside,
        allowed: areaResult.allowed,
      };
    });

    if (candidates.length === 0) {
      throw httpError('ADDRESS_NOT_FOUND', 404);
    }
    if (geofenceService.resolveGeofenceMode() === 'ENFORCE' &&
        !candidates.some((candidate) => candidate.inside)) {
      throw httpError('ADDRESS_OUTSIDE_ALLOWED_AREA', 422);
    }
    return {
      mode: geofenceService.resolveGeofenceMode(),
      area: geofenceService.area,
      candidates,
    };
  }

  return { geocodeAddress };
}

module.exports = {
  GOOGLE_GEOCODING_URL,
  OFFICIAL_BOUNDS,
  createGeocodingService,
  geocodingService: createGeocodingService(),
  messages,
};
