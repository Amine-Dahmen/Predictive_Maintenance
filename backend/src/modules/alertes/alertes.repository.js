const { query } = require('../../config/db');

const COLS = `a.id, a.machine_id AS "machineId", m.code AS "machineCode", m.nom AS "machineNom",
  a.capteur_id AS "capteurId", c.identifiant AS "capteur", c.type AS "typeMesure", c.unite,
  a.niveau, a.valeur, a.seuil_depasse AS "seuilDepasse", a.statut,
  a.prise_en_compte_par AS "priseEnCompteParId", a.prise_en_compte_at AS "priseEnCompteAt",
  a.cloturee_at AS "clotureeAt", a.commentaire, a.created_at AS "createdAt",
  (a.statut = 'OUVERTE' AND a.created_at < NOW() - INTERVAL '30 minutes') AS "enRetard",
  a.mesure_at AS "mesureAt", a.fausse_alerte AS "fausseAlerte",
  ROUND(EXTRACT(EPOCH FROM (a.created_at - a.mesure_at))::numeric, 1)::float AS "delaiDetectionS"`;
// delaiDetectionS (US-43) : temps entre la mesure (heure de l'ESP32) et la création de l'alerte par le backend
const FROM = 'FROM alertes a JOIN machines m ON m.id = a.machine_id JOIN capteurs c ON c.id = a.capteur_id';

async function list({ from, to, machineId, statut, niveau, fausseAlerte, limit }) {
  const params = [from, to]; const where = ['a.created_at BETWEEN $1 AND $2'];
  for (const [val, col] of [[machineId, 'a.machine_id'], [statut, 'a.statut'], [niveau, 'a.niveau'], [fausseAlerte, 'a.fausse_alerte']]) {
    if (val !== undefined) { params.push(val); where.push(`${col} = $${params.length}`); }
  }
  params.push(limit);
  return (await query(`SELECT ${COLS} ${FROM} WHERE ${where.join(' AND ')} ORDER BY a.created_at DESC LIMIT $${params.length}`, params)).rows;
}

const countParMachine = async ({ from, to }) => (await query(
  `SELECT m.id AS "machineId", m.code, m.nom, COUNT(a.id)::int AS "nbAlertes",
          (COUNT(a.id) FILTER (WHERE a.niveau = 'CRITIQUE'))::int AS "nbCritiques"
   FROM machines m LEFT JOIN alertes a ON a.machine_id = m.id AND a.created_at BETWEEN $1 AND $2 AND NOT a.fausse_alerte
   GROUP BY m.id ORDER BY "nbAlertes" DESC`, [from, to],
)).rows;

const findById = async (id) => (await query(`SELECT ${COLS} ${FROM} WHERE a.id = $1`, [id])).rows[0];

const findOpenByCapteur = async (capteurId) =>
  (await query(`SELECT * FROM alertes WHERE capteur_id = $1 AND statut <> 'CLOTUREE'`, [capteurId])).rows[0];

// ON CONFLICT : l'index unique partiel garantit une seule alerte ouverte par capteur, même en cas de messages simultanés
const create = async ({ machineId, capteurId, mesureId, mesureAt, niveau, valeur, seuil }) => (await query(
  `INSERT INTO alertes (machine_id, capteur_id, mesure_id, mesure_at, niveau, valeur, seuil_depasse)
   VALUES ($1, $2, $3, $4, $5, $6, $7)
   ON CONFLICT (capteur_id) WHERE statut <> 'CLOTUREE' DO NOTHING RETURNING id`,
  [machineId, capteurId, mesureId, mesureAt, niveau, valeur, seuil],
)).rows[0];

// Une alerte ouverte de niveau ALERTE passe à CRITIQUE si la situation s'aggrave
const escalate = (id, mesureId, valeur, seuil) => query(
  `UPDATE alertes SET niveau = 'CRITIQUE', mesure_id = $2, valeur = $3, seuil_depasse = $4 WHERE id = $1 AND niveau = 'ALERTE'`,
  [id, mesureId, valeur, seuil],
);

const prendreEnCompte = async (id, userId) => (await query(
  `UPDATE alertes SET statut = 'PRISE_EN_COMPTE', prise_en_compte_par = $2, prise_en_compte_at = NOW()
   WHERE id = $1 AND statut = 'OUVERTE' RETURNING id`, [id, userId],
)).rows[0];

const cloturer = async (id, commentaire, db = { query }) => (await db.query(
  `UPDATE alertes SET statut = 'CLOTUREE', cloturee_at = NOW(), commentaire = COALESCE($2, commentaire)
   WHERE id = $1 AND statut <> 'CLOTUREE' RETURNING id, machine_id AS "machineId"`, [id, commentaire],
)).rows[0];

// US-31 : une fausse alerte est clôturée et marquée ; elle sort des statistiques
const marquerFausseAlerte = async (id, commentaire) => (await query(
  `UPDATE alertes SET statut = 'CLOTUREE', fausse_alerte = TRUE, cloturee_at = COALESCE(cloturee_at, NOW()),
     commentaire = $2
   WHERE id = $1 AND NOT fausse_alerte RETURNING id, machine_id AS "machineId"`, [id, commentaire],
)).rows[0];

module.exports = { marquerFausseAlerte, list, countParMachine, findById, findOpenByCapteur, create, escalate, prendreEnCompte, cloturer };
