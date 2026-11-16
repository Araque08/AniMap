
const sharp = require('sharp');

/**
 * Genera una miniatura optimizada para mostrar mascotas
 * en tarjetas y perfiles de AniMap.
 *
 * No modifica la fotografía original.
 */
async function generarMiniatura(bufferOriginal) {
  if (!Buffer.isBuffer(bufferOriginal) || bufferOriginal.length === 0) {
    throw new Error('La imagen original no es válida.');
  }

  const miniatura = await sharp(bufferOriginal, {
    limitInputPixels: 40000000,
  })
    .rotate()
    .resize(320, 320, {
      fit: 'cover',
      position: 'attention',
      withoutEnlargement: true,
    })
    .webp({
      quality: 75,
      effort: 4,
    })
    .toBuffer();

  return miniatura;
}

module.exports = {
  generarMiniatura,
};
