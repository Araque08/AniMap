
const COLORES_PERMITIDOS = [
  'Negro',
  'Blanco',
  'Gris',
  'Café',
  'Marrón',
  'Beige',
  'Crema',
  'Dorado',
  'Amarillo',
  'Naranja',
  'Canela',
  'Chocolate',
  'Rojizo',
  'Atigrado',
  'Azul grisáceo',
];

function validarColoresMascota(valor) {
  if (typeof valor !== 'string') {
    return {
      ok: false,
      message: 'Debes seleccionar al menos un color',
    };
  }

  const colores = valor.split(',').map(
    (color) => color.trim()
  );

  if (colores.length < 1 || colores.length > 5 ||
      colores.some((color) => color.length === 0)) {
    return {
      ok: false,
      message: 'Debes seleccionar entre 1 y 5 colores',
    };
  }

  const coloresNormalizados = [];

  for (const color of colores) {
    const colorValido = COLORES_PERMITIDOS.find(
      (permitido) =>
        permitido.toLowerCase() === color.toLowerCase()
    );

    if (!colorValido) {
      return {
        ok: false,
        message: `El color "${color}" no está permitido`,
      };
    }

    if (coloresNormalizados.includes(colorValido)) {
      return {
        ok: false,
        message: 'No puedes seleccionar colores repetidos',
      };
    }

    coloresNormalizados.push(colorValido);
  }

  const coloresFinales = coloresNormalizados.join(', ');

  if (coloresFinales.length > 100) {
    return {
      ok: false,
      message: 'La información de colores es demasiado larga',
    };
  }

  return {
    ok: true,
    color: coloresFinales,
  };
}

module.exports = {
  validarColoresMascota,
};
