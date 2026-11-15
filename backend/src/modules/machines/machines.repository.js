const { query } = require('../../config/db');
const AppError = require('../../utils/AppError');

const MACHINE_COLS = `m.id, m.code, m.nom, m.emplacement, m.etat, m.created_at AS "createdAt", m.updated_at AS "updatedAt",
  m.cout_horaire_arret::float AS "coutHoraireArret", m.firmware_version AS "firmwareVersion"`;
const CAPTEUR_COLS = `c.id, c.identifiant, c.machine_id AS "machineId", c.type, c.unite, c.actif, c.en_ligne AS "enLigne",
  c.derniere_mesure_at AS "derniereMesureAt", c.calibration_gain AS "calibrationGain",
  c.calibration_offset AS "calibrationOffset", c.calibre_at AS "calibreAt", c.retire_at AS "retireAt",
  c.remplace_par AS "remplacePar"`;

async function list({ etat, recherche }) {
  const where = []; const params = [];
  if (etat) { params.push(etat); where.push(`m.etat = $${params.length}`); }
  if (recherche) { params.push(`%${recherche}%`); where.push(`(m.code ILIKE $${params.length} OR m.nom ILIKE $${params.length})`); }
  const { rows } = await query(
    `SELECT ${MACHINE_COLS}, (SELECT COUNT(*)::int FROM capteurs c WHERE c.machine_id = m.id) AS "nbCapteurs"
     FROM machines m ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY m.code`, params,
  );
  return rows;
}

const findById = async (id) => (await query(`SELECT ${MACHINE_COLS} FROM machines m WHERE m.id = $1`, [id])).rows[0];

async function create({ code, nom, emplacement }, db = { query }) {
  try {
    return (await db.query(
      `INSERT INTO machines AS m (code, nom, emplacement) VALUES ($1, $2, $3) RETURNING ${MACHINE_COLS}`,
      [code, nom, emplacement || null],
    )).rows[0];
  } catch (e) {
    if (e.code === '23505') throw AppError.conflict(`Une machine avec le code ${code} existe déjà`);
    throw e;
  }
}

async function update(id, data) {
  const sets = []; const params = [id];
  for (const [k, col] of [['code', 'code'], ['nom', 'nom'], ['emplacement', 'emplacement'], ['coutHoraireArret', 'cout_horaire_arret']]) {
    if (data[k] !== undefined) { params.push(data[k]); sets.push(`${col} = $${params.length}`); }
  }
  return (await query(`UPDATE machines AS m SET ${sets.join(', ')}, updated_at = NOW() WHERE m.id = $1 RETURNING ${MACHINE_COLS}`, params)).rows[0];
}

// Capteurs d'une machine avec leur dernière valeur
async function capteursWithLastValue(machineId) {
  return (await query(
    `SELECT ${CAPTEUR_COLS}, lm.valeur AS "derniereValeur"
     FROM capteurs c
     LEFT JOIN LATERAL (SELECT valeur FROM mesures WHERE capteur_id = c.id ORDER BY horodatage DESC LIMIT 1) lm ON TRUE
     WHERE c.machine_id = $1 ORDER BY c.actif DESC, c.type, c.id`, [machineId],
  )).rows;
}

async function createCapteur(machineId, { identifiant, type, unite }, db = { query }) {
  try {
    return (await db.query(
      `INSERT INTO capteurs AS c (identifiant, machine_id, type, unite) VALUES ($1, $2, $3, $4) RETURNING ${CAPTEUR_COLS}`,
      [identifiant, machineId, type, unite],
    )).rows[0];
  } catch (e) {
    if (e.code === '23505') throw AppError.conflict(`Le capteur ${identifiant} existe déjà`);
    throw e;
  }
}

async function updateCapteur(id, data) {
  const sets = []; const params = [id];
  for (const k of ['actif', 'unite']) {
    if (data[k] !== undefined) { params.push(data[k]); sets.push(`${k} = $${params.length}`); }
  }
  return (await query(`UPDATE capteurs AS c SET ${sets.join(', ')} WHERE c.id = $1 RETURNING ${CAPTEUR_COLS}`, params)).rows[0];
}

const seuils = async (machineId) => (await query(
  `SELECT id, type_mesure AS "typeMesure", seuil_alerte AS "seuilAlerte", seuil_critique AS "seuilCritique",
          modifie_par AS "modifiePar", updated_at AS "updatedAt"
   FROM seuils WHERE machine_id = $1 ORDER BY type_mesure`, [machineId],
)).rows;

const upsertSeuil = async (machineId, typeMesure, { seuilAlerte, seuilCritique }, userId, db = { query }) => (await db.query(
  `INSERT INTO seuils (machine_id, type_mesure, seuil_alerte, seuil_critique, modifie_par)
   VALUES ($1, $2, $3, $4, $5)
   ON CONFLICT (machine_id, type_mesure) DO UPDATE
     SET seuil_alerte = EXCLUDED.seuil_alerte, seuil_critique = EXCLUDED.seuil_critique,
         modifie_par = EXCLUDED.modifie_par, updated_at = NOW()
   RETURNING id, type_mesure AS "typeMesure", seuil_alerte AS "seuilAlerte", seuil_critique AS "seuilCritique", updated_at AS "updatedAt"`,
  [machineId, typeMesure, seuilAlerte, seuilCritique, userId],
)).rows[0];

async function mesures(machineId, { type, from, to, limit }) {
  const params = [machineId, from, to, limit];
  let typeFilter = '';
  if (type) { params.push(type); typeFilter = `AND c.type = $${params.length}`; }
  return (await query(
    `SELECT me.id, me.valeur, me.horodatage, c.id AS "capteurId", c.identifiant, c.type, c.unite
     FROM mesures me JOIN capteurs c ON c.id = me.capteur_id
     WHERE c.machine_id = $1 AND me.horodatage BETWEEN $2 AND $3 ${typeFilter}
     ORDER BY me.horodatage DESC LIMIT $4`, params,
  )).rows;
}

// Historique : alertes + interventions, triés du plus récent au plus ancien (PB-10)
async function historique(machineId, { from, to }) {
  return (await query(
    `SELECT * FROM (
       SELECT 'ALERTE' AS categorie, a.id, a.created_at AS date, a.niveau::text AS sous_type,
              CASE WHEN a.fausse_alerte THEN 'FAUSSE_ALERTE' ELSE a.statut::text END AS statut,
              CONCAT('Valeur ', a.valeur, ' (seuil ', a.seuil_depasse, ')') AS libelle
       FROM alertes a WHERE a.machine_id = $1 AND a.created_at BETWEEN $2 AND $3
       UNION ALL
       SELECT 'INTERVENTION', i.id, i.created_at, i.type::text, i.statut::text, i.description
       FROM interventions i WHERE i.machine_id = $1 AND i.created_at BETWEEN $2 AND $3
     ) h ORDER BY date DESC`, [machineId, from, to],
  )).rows;
}

const findCapteur = async (id, db = { query }) =>
  (await db.query(`SELECT ${CAPTEUR_COLS} FROM capteurs c WHERE c.id = $1`, [id])).rows[0];

// US-39 : la dernière valeur enregistrée sert à calculer un offset de « mise à zéro »
const derniereValeur = async (capteurId) => (await query(
  'SELECT valeur FROM mesures WHERE capteur_id = $1 ORDER BY horodatage DESC LIMIT 1', [capteurId],
)).rows[0]?.valeur;

const setCalibration = async (id, { gain, offset }, userId) => (await query(
  `UPDATE capteurs AS c SET calibration_gain = $2, calibration_offset = $3, calibre_at = NOW(), calibre_par = $4
   WHERE c.id = $1 RETURNING ${CAPTEUR_COLS}`, [id, gain, offset, userId],
)).rows[0];

// US-37 : l'ancien capteur est retiré, ses alertes ouvertes sont clôturées, le nouveau prend sa place
async function remplacerCapteur(ancien, identifiant, db) {
  const nouveau = await createCapteur(ancien.machineId, { identifiant, type: ancien.type, unite: ancien.unite }, db);
  await db.query('UPDATE capteurs SET actif = FALSE, en_ligne = FALSE, retire_at = NOW(), remplace_par = $2 WHERE id = $1',
    [ancien.id, nouveau.id]);
  await db.query(`UPDATE alertes SET statut = 'CLOTUREE', cloturee_at = NOW(),
                    commentaire = COALESCE(commentaire, 'Capteur remplacé')
                  WHERE capteur_id = $1 AND statut <> 'CLOTUREE'`, [ancien.id]);
  return nouveau;
}

const identifiantExiste = async (identifiant, db = { query }) =>
  (await db.query('SELECT 1 FROM capteurs WHERE identifiant = $1', [identifiant])).rowCount > 0;

// US-32 : statistiques par machine et par type de mesure sur la période, et série temporelle agrégée
async function comparaison(ids, { from, to, type }) {
  const stats = (await query(
    `SELECT c.machine_id AS "machineId", c.type, COUNT(me.id)::int AS nb,
            AVG(me.valeur)::float AS moyenne, MIN(me.valeur)::float AS minimum, MAX(me.valeur)::float AS maximum,
            STDDEV_SAMP(me.valeur)::float AS "ecartType"
     FROM capteurs c JOIN mesures me ON me.capteur_id = c.id
     WHERE c.machine_id = ANY($1::int[]) AND me.horodatage BETWEEN $2 AND $3 AND ($4::type_mesure IS NULL OR c.type = $4)
     GROUP BY c.machine_id, c.type ORDER BY c.machine_id, c.type`, [ids, from, to, type ?? null],
  )).rows;
  // Pas d'agrégation choisi pour obtenir environ 60 points sur la période
  const pasS = Math.max(60, Math.round((to - from) / 1000 / 60));
  const series = type ? (await query(
    `SELECT c.machine_id AS "machineId", date_bin(make_interval(secs => $5), me.horodatage, $2) AS t,
            AVG(me.valeur)::float AS v
     FROM capteurs c JOIN mesures me ON me.capteur_id = c.id
     WHERE c.machine_id = ANY($1::int[]) AND me.horodatage BETWEEN $2 AND $3 AND c.type = $4
     GROUP BY 1, 2 ORDER BY 1, 2`, [ids, from, to, type, pasS],
  )).rows : [];
  const alertes = (await query(
    `SELECT machine_id AS "machineId", COUNT(*)::int AS nb,
            (COUNT(*) FILTER (WHERE niveau = 'CRITIQUE'))::int AS critiques
     FROM alertes WHERE machine_id = ANY($1::int[]) AND created_at BETWEEN $2 AND $3 AND NOT fausse_alerte
     GROUP BY machine_id`, [ids, from, to],
  )).rows;
  return { stats, series, alertes, pasS };
}

// US-40 : mesures archivées (moyennes horaires)
const mesuresHoraires = async (machineId, { type, from, to }) => (await query(
  `SELECT mh.heure, mh.nb, mh.moyenne, mh.minimum, mh.maximum, c.id AS "capteurId", c.type, c.unite
   FROM mesures_horaires mh JOIN capteurs c ON c.id = mh.capteur_id
   WHERE c.machine_id = $1 AND mh.heure BETWEEN $2 AND $3 AND ($4::type_mesure IS NULL OR c.type = $4)
   ORDER BY mh.heure`, [machineId, from, to, type ?? null],
)).rows;

module.exports = {
  findCapteur, derniereValeur, setCalibration, remplacerCapteur, identifiantExiste, comparaison, mesuresHoraires,
  list, findById, create, update, capteursWithLastValue, createCapteur, updateCapteur, seuils, upsertSeuil, mesures, historique };
