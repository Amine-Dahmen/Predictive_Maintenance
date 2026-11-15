// US-46 : mise à jour du firmware des cartes ESP32 à distance (OTA).
//
//  1. npm run firmware:publier  copie le firmware (partie_embarque/src, sans credentials.py) dans
//     FIRMWARE_DIR/<version>/ avec un manifest.json (taille + SHA-256 de chaque fichier)
//  2. POST /machines/:id/firmware {version}  crée un déploiement et publie sur MQTT
//     usine/machines/<code>/ota : {version, deploiement, url, fichiers:[{nom, taille, sha256}]}
//     Le topic est protégé par l'ACL : seule la carte de la machine le lit, seul le backend l'écrit.
//  3. la carte télécharge chaque fichier sur GET /api/firmware/telechargement/<jeton>/<fichier>
//     (jeton aléatoire, haché en base, valable 30 min), vérifie le SHA-256 reçu par MQTT, remplace
//     ses fichiers en gardant une copie .bak, redémarre ; elle revient à l'ancienne version si la
//     nouvelle ne démarre pas (voir partie_embarque/src/boot.py)
//  4. la carte publie l'avancement sur usine/machines/<code>/ota/statut :
//     {version, deploiement, statut: EN_COURS | REUSSI | ECHEC | DEMARRE, message}
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const env = require('../../config/env');
const { query } = require('../../config/db');
const AppError = require('../../utils/AppError');
const logger = require('../../utils/logger');
const { publish } = require('../../realtime/eventBus');

const VALIDITE_JETON_MS = 30 * 60 * 1000;
const VERSION_RE = /^[0-9A-Za-z._-]{1,40}$/;
const STATUTS_CARTE = ['EN_COURS', 'REUSSI', 'ECHEC', 'DEMARRE'];

const dossier = () => path.resolve(env.FIRMWARE_DIR);
const hash = (t) => crypto.createHash('sha256').update(t).digest('hex');

let publishMqtt = null; // fourni par le client MQTT une fois connecté
const init = (fn) => { publishMqtt = fn; };

function lireManifest(version) {
  if (!VERSION_RE.test(version)) return null;
  try {
    const m = JSON.parse(fs.readFileSync(path.join(dossier(), version, 'manifest.json'), 'utf8'));
    return m && Array.isArray(m.fichiers) ? m : null;
  } catch {
    return null;
  }
}

function versions() {
  let noms = [];
  try { noms = fs.readdirSync(dossier(), { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name); } catch { /* dossier absent */ }
  return noms.map(lireManifest).filter(Boolean)
    .map((m) => ({ version: m.version, publieLe: m.publieLe, fichiers: m.fichiers.length, taille: m.fichiers.reduce((a, f) => a + f.taille, 0) }))
    .sort((a, b) => String(b.publieLe).localeCompare(String(a.publieLe)));
}

// Adresse de l'API vue par les cartes : PUBLIC_BASE_URL, sinon l'IPv4 du PC sur le réseau local
function adresseLocale() {
  const candidats = Object.values(os.networkInterfaces()).flat()
    .filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
  return candidats.find((a) => /^(192\.168|10\.)/.test(a)) || candidats.find((a) => !a.startsWith('172.')) || candidats[0] || 'localhost';
}
const baseUrl = () => (env.PUBLIC_BASE_URL || `http://${adresseLocale()}:${env.PORT}`).replace(/\/$/, '');

async function deployer(machineId, version, user) {
  const { rows: [machine] } = await query('SELECT id, code FROM machines WHERE id = $1', [machineId]);
  if (!machine) throw AppError.notFound('Machine introuvable');
  const manifest = lireManifest(version);
  if (!manifest) throw AppError.badRequest(`Version de firmware inconnue : ${version}`);
  if (!publishMqtt) throw AppError.conflict('Broker MQTT injoignable : la carte ne peut pas être prévenue');

  const jeton = crypto.randomBytes(24).toString('hex');
  const { rows: [d] } = await query(
    `INSERT INTO firmware_deploiements (machine_id, version, lance_par, token_hash, expire_at)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [machine.id, version, user.id, hash(jeton), new Date(Date.now() + VALIDITE_JETON_MS)],
  );
  const ordre = {
    version, deploiement: d.id,
    url: `${baseUrl()}/api/firmware/telechargement/${jeton}`,
    fichiers: manifest.fichiers.map(({ nom, taille, sha256 }) => ({ nom, taille, sha256 })),
  };
  publishMqtt(machine.code, JSON.stringify(ordre));
  logger.info(`Firmware ${version} envoyé à la carte ${machine.code} (déploiement #${d.id})`);
  return deploiement(d.id);
}

const COLS = `d.id, d.machine_id AS "machineId", m.code AS "machineCode", d.version, d.statut, d.message,
  d.lance_par AS "lanceParId", d.created_at AS "createdAt", d.updated_at AS "updatedAt"`;
const deploiement = async (id) =>
  (await query(`SELECT ${COLS} FROM firmware_deploiements d JOIN machines m ON m.id = d.machine_id WHERE d.id = $1`, [id])).rows[0];
const historique = async (machineId) => (await query(
  `SELECT ${COLS} FROM firmware_deploiements d JOIN machines m ON m.id = d.machine_id
   WHERE d.machine_id = $1 ORDER BY d.created_at DESC LIMIT 20`, [machineId],
)).rows;

// Téléchargement par la carte : le jeton doit être valide et le fichier listé dans le manifest
async function fichierPourJeton(jeton, nom) {
  if (!/^[0-9a-f]{48}$/.test(jeton)) throw AppError.notFound('Lien invalide');
  const { rows: [d] } = await query(
    `SELECT id, version FROM firmware_deploiements WHERE token_hash = $1 AND expire_at > NOW()
       AND statut IN ('ENVOYE', 'EN_COURS')`, [hash(jeton)],
  );
  if (!d) throw AppError.notFound('Lien expiré ou invalide');
  const manifest = lireManifest(d.version);
  if (!manifest || !manifest.fichiers.some((f) => f.nom === nom)) throw AppError.notFound('Fichier inconnu');
  return path.join(dossier(), d.version, path.basename(nom));
}

// Message de la carte sur usine/machines/<code>/ota/statut
async function statutCarte(codeMachine, buffer) {
  let msg;
  try { msg = JSON.parse(buffer.toString('utf8')); } catch { return; }
  if (!msg || !STATUTS_CARTE.includes(msg.statut)) return;
  const version = typeof msg.version === 'string' && VERSION_RE.test(msg.version) ? msg.version : null;
  const { rows: [machine] } = await query('SELECT id FROM machines WHERE code = $1', [codeMachine]);
  if (!machine) return;
  if (version && (msg.statut === 'REUSSI' || msg.statut === 'DEMARRE')) {
    await query('UPDATE machines SET firmware_version = $2 WHERE id = $1', [machine.id, version]);
  }
  if (msg.statut === 'DEMARRE' || !Number.isInteger(msg.deploiement)) return;
  const { rows: [d] } = await query(
    `UPDATE firmware_deploiements SET statut = $3::varchar, message = $4, updated_at = NOW(),
       expire_at = CASE WHEN $3::varchar IN ('REUSSI', 'ECHEC') THEN NOW() ELSE expire_at END
     WHERE id = $1 AND machine_id = $2 AND statut NOT IN ('REUSSI', 'ECHEC') RETURNING id`,
    [msg.deploiement, machine.id, msg.statut, msg.message ? String(msg.message).slice(0, 500) : null],
  );
  if (!d) return;
  const maj = await deploiement(d.id);
  (msg.statut === 'ECHEC' ? logger.warn : logger.info)(`Firmware ${maj.version} sur ${codeMachine} : ${msg.statut}${msg.message ? ` (${msg.message})` : ''}`);
  publish('firmware.maj', maj, { roles: ['RESPONSABLE', 'DIRECTEUR'] });
}

module.exports = { init, versions, deployer, historique, fichierPourJeton, statutCarte, lireManifest, baseUrl };
