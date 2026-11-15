const { query } = require('../../config/db');

const COLS = `i.id, i.type, i.priorite, i.statut, i.description,
  i.machine_id AS "machineId", m.code AS "machineCode", m.nom AS "machineNom", m.emplacement AS "machineEmplacement",
  i.alerte_id AS "alerteId", i.technicien_id AS "technicienId",
  t.nom AS "technicienNom", t.prenom AS "technicienPrenom",
  i.date_prevue AS "datePrevue", i.echeance, i.debut_panne AS "debutPanne",
  i.date_debut AS "dateDebut", i.date_fin AS "dateFin", i.resultat,
  i.cree_par AS "creeParId", i.created_at AS "createdAt",
  (i.statut NOT IN ('CLOTUREE','ANNULEE') AND i.echeance IS NOT NULL AND i.echeance < NOW()) AS "enRetard",
  CASE WHEN i.date_fin IS NOT NULL AND i.date_debut IS NOT NULL
       THEN ROUND(EXTRACT(EPOCH FROM (i.date_fin - i.date_debut)) / 60) END AS "dureeReelleMin"`;
const FROM = 'FROM interventions i JOIN machines m ON m.id = i.machine_id LEFT JOIN utilisateurs t ON t.id = i.technicien_id';

const ORDER_PRIORITE = `CASE i.priorite WHEN 'URGENTE' THEN 1 WHEN 'HAUTE' THEN 2 WHEN 'MOYENNE' THEN 3 ELSE 4 END`;

async function list(f) {
  const where = []; const params = [];
  for (const [val, col] of [[f.statut, 'i.statut'], [f.type, 'i.type'], [f.machineId, 'i.machine_id'], [f.technicienId, 'i.technicien_id']]) {
    if (val !== undefined) { params.push(val); where.push(`${col} = $${params.length}`); }
  }
  if (f.enRetard) where.push(`i.statut NOT IN ('CLOTUREE','ANNULEE') AND i.echeance < NOW()`);
  if (f.sansTechnicien) where.push('i.technicien_id IS NULL');
  return (await query(
    `SELECT ${COLS} ${FROM} ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
     ORDER BY ${ORDER_PRIORITE}, i.echeance NULLS LAST, i.created_at DESC`, params,
  )).rows;
}

const findById = async (id, db = { query }) => (await db.query(`SELECT ${COLS} ${FROM} WHERE i.id = $1`, [id])).rows[0];

const lockById = async (id, db) => (await db.query('SELECT * FROM interventions WHERE id = $1 FOR UPDATE', [id])).rows[0];

const create = async (d, db = { query }) => (await db.query(
  `INSERT INTO interventions (machine_id, alerte_id, type, priorite, description, date_prevue, echeance, debut_panne, cree_par)
   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id`,
  [d.machineId, d.alerteId || null, d.type, d.priorite, d.description, d.datePrevue || null, d.echeance || null, d.debutPanne || null, d.creePar],
)).rows[0].id;

async function update(id, data, db = { query }) {
  const map = { description: 'description', priorite: 'priorite', datePrevue: 'date_prevue', echeance: 'echeance',
    technicienId: 'technicien_id', statut: 'statut', dateDebut: 'date_debut', dateFin: 'date_fin', resultat: 'resultat' };
  const sets = []; const params = [id];
  for (const [k, col] of Object.entries(map)) {
    if (data[k] !== undefined) { params.push(data[k]); sets.push(`${col} = $${params.length}`); }
  }
  await db.query(`UPDATE interventions SET ${sets.join(', ')}, updated_at = NOW() WHERE id = $1`, params);
}

// Autres interventions du technicien qui chevauchent le même jour (PB-30, PB-31)
const conflitsTechnicien = async (technicienId, date, excludeId) => (await query(
  `SELECT id FROM interventions
   WHERE technicien_id = $1 AND id <> $3 AND statut IN ('AFFECTEE','EN_COURS')
     AND COALESCE(date_prevue, echeance)::date = $2::date`, [technicienId, date, excludeId],
)).rows.map((r) => r.id);

const findTechnicienActif = async (id) => (await query(
  `SELECT id, nom, prenom FROM utilisateurs WHERE id = $1 AND role = 'TECHNICIEN' AND statut = 'ACTIF'`, [id],
)).rows[0];

const setTechnicienDisponible = (technicienId, db = { query }) => db.query(
  `UPDATE utilisateurs SET disponible = NOT EXISTS (
     SELECT 1 FROM interventions WHERE technicien_id = $1 AND statut = 'EN_COURS') WHERE id = $1`, [technicienId],
);

// ---------- Compte rendu ----------
const CR_COLS = `id, intervention_id AS "interventionId", diagnostic, actions, pieces_utilisees AS "piecesUtilisees",
  brouillon, updated_at AS "updatedAt"`;

const findCompteRendu = async (interventionId, db = { query }) =>
  (await db.query(`SELECT ${CR_COLS} FROM comptes_rendus WHERE intervention_id = $1`, [interventionId])).rows[0];

const upsertCompteRendu = async (interventionId, d) => (await query(
  `INSERT INTO comptes_rendus (intervention_id, diagnostic, actions, pieces_utilisees)
   VALUES ($1, $2, $3, $4)
   ON CONFLICT (intervention_id) DO UPDATE SET
     diagnostic = COALESCE(EXCLUDED.diagnostic, comptes_rendus.diagnostic),
     actions = COALESCE(EXCLUDED.actions, comptes_rendus.actions),
     pieces_utilisees = COALESCE(EXCLUDED.pieces_utilisees, comptes_rendus.pieces_utilisees),
     updated_at = NOW()
   RETURNING ${CR_COLS}`,
  [interventionId, d.diagnostic ?? null, d.actions ?? null, d.piecesUtilisees ?? null],
)).rows[0];

const finaliserCompteRendu = (interventionId, db) =>
  db.query('UPDATE comptes_rendus SET brouillon = FALSE, updated_at = NOW() WHERE intervention_id = $1', [interventionId]);

// Prise en charge par un technicien : seulement si personne ne l'a déjà prise (verrou par la condition)
const prendreEnCharge = async (id, technicienId) => (await query(
  `UPDATE interventions SET technicien_id = $2, statut = 'AFFECTEE',
     echeance = COALESCE(echeance, NOW() + INTERVAL '24 hours'), updated_at = NOW()
   WHERE id = $1 AND statut = 'A_AFFECTER' AND technicien_id IS NULL RETURNING id`, [id, technicienId],
)).rows[0];

module.exports = {
  prendreEnCharge,
  list, findById, lockById, create, update, conflitsTechnicien, findTechnicienActif, setTechnicienDisponible,
  findCompteRendu, upsertCompteRendu, finaliserCompteRendu,
};
