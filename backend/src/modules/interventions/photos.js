// US-25 : photos jointes à une intervention.
// Sécurité : 5 Mo maximum, JPEG ou PNG vérifié sur le contenu (pas sur l'extension ni l'en-tête du client),
// nom de fichier généré par le serveur, fichiers servis uniquement à un utilisateur qui voit l'intervention.
const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');
const env = require('../../config/env');
const { query } = require('../../config/db');
const AppError = require('../../utils/AppError');

const TAILLE_MAX = 5 * 1024 * 1024;
const MAX_PAR_INTERVENTION = 10;
const dossier = () => path.resolve(env.UPLOADS_DIR, 'interventions');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: TAILLE_MAX, files: 1, fields: 2 },
}).single('photo');

// Middleware : traduit les erreurs de multer en erreurs de l'API
function recevoirPhoto(req, res, next) {
  upload(req, res, (err) => {
    if (!err) return next();
    if (err.code === 'LIMIT_FILE_SIZE') return next(AppError.badRequest('Photo trop volumineuse (5 Mo maximum)'));
    return next(AppError.badRequest(`Envoi de la photo impossible : ${err.message}`));
  });
}

function typeImage(buffer) {
  if (buffer.length > 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return { mime: 'image/jpeg', ext: 'jpg' };
  if (buffer.length > 8 && buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return { mime: 'image/png', ext: 'png' };
  }
  return null;
}

const COLS = `id, intervention_id AS "interventionId", type_mime AS "typeMime", taille, legende,
  ajoute_par AS "ajouteParId", created_at AS "createdAt"`;

const lister = async (interventionId) =>
  (await query(`SELECT ${COLS} FROM intervention_photos WHERE intervention_id = $1 ORDER BY created_at`, [interventionId])).rows;

async function ajouter(intervention, file, legende, user) {
  if (!file) throw AppError.badRequest('Aucune photo reçue (champ « photo »)');
  const type = typeImage(file.buffer);
  if (!type) throw AppError.badRequest('Format non accepté : JPEG ou PNG uniquement');
  if (user.role === 'TECHNICIEN' && !['EN_COURS', 'CLOTUREE'].includes(intervention.statut)) {
    throw AppError.conflict("Démarrez l'intervention avant d'y joindre des photos");
  }
  const { rows: [{ n }] } = await query('SELECT COUNT(*)::int AS n FROM intervention_photos WHERE intervention_id = $1', [intervention.id]);
  if (n >= MAX_PAR_INTERVENTION) throw AppError.conflict(`${MAX_PAR_INTERVENTION} photos maximum par intervention`);

  const fichier = `${intervention.id}-${crypto.randomBytes(12).toString('hex')}.${type.ext}`;
  await fs.mkdir(dossier(), { recursive: true });
  await fs.writeFile(path.join(dossier(), fichier), file.buffer, { flag: 'wx' });
  const { rows } = await query(
    `INSERT INTO intervention_photos (intervention_id, fichier, type_mime, taille, legende, ajoute_par)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING ${COLS}`,
    [intervention.id, fichier, type.mime, file.size, legende ? String(legende).slice(0, 200) : null, user.id],
  );
  return rows[0];
}

async function fichier(interventionId, photoId) {
  const { rows } = await query(
    'SELECT fichier, type_mime FROM intervention_photos WHERE id = $1 AND intervention_id = $2', [photoId, interventionId],
  );
  if (!rows[0]) throw AppError.notFound('Photo introuvable');
  return { chemin: path.join(dossier(), path.basename(rows[0].fichier)), mime: rows[0].type_mime };
}

async function supprimer(interventionId, photoId, user) {
  const { rows } = await query(
    `DELETE FROM intervention_photos WHERE id = $1 AND intervention_id = $2
       AND ($3::text <> 'TECHNICIEN' OR ajoute_par = $4) RETURNING fichier`,
    [photoId, interventionId, user.role, user.id],
  );
  if (!rows[0]) throw AppError.notFound('Photo introuvable');
  await fs.rm(path.join(dossier(), path.basename(rows[0].fichier)), { force: true });
}

module.exports = { recevoirPhoto, typeImage, lister, ajouter, fichier, supprimer, TAILLE_MAX };
