const { query } = require('../../config/db');

const COLS = `o.id, o.numero, o.machine_id AS "machineId", m.code AS "machineCode", o.produit,
  o.quantite_prevue AS "quantitePrevue", o.quantite_produite AS "quantiteProduite", o.quantite_rebutee AS "quantiteRebutee",
  o.temps_cycle_s AS "tempsCycleS", o.date_debut AS "dateDebut", o.date_fin AS "dateFin", o.statut, o.created_at AS "createdAt"`;
const FROM = 'FROM ordres_fabrication o JOIN machines m ON m.id = o.machine_id';

const MAP = { produit: 'produit', quantitePrevue: 'quantite_prevue', quantiteProduite: 'quantite_produite',
  quantiteRebutee: 'quantite_rebutee', tempsCycleS: 'temps_cycle_s', dateDebut: 'date_debut', dateFin: 'date_fin', statut: 'statut' };

async function list({ statut, machineId, from, to }) {
  const where = []; const params = [];
  if (statut) { params.push(statut); where.push(`o.statut = $${params.length}`); }
  if (machineId) { params.push(machineId); where.push(`o.machine_id = $${params.length}`); }
  if (from) { params.push(from); where.push(`COALESCE(o.date_fin, o.date_debut, o.created_at) >= $${params.length}`); }
  if (to) { params.push(to); where.push(`COALESCE(o.date_debut, o.created_at) <= $${params.length}`); }
  return (await query(`SELECT ${COLS} ${FROM} ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY o.created_at DESC`, params)).rows;
}

const findById = async (id) => (await query(`SELECT ${COLS} ${FROM} WHERE o.id = $1`, [id])).rows[0];

const create = async (d) => (await query(
  `INSERT INTO ordres_fabrication (numero, machine_id, produit, quantite_prevue, temps_cycle_s, date_debut, date_fin)
   VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
  [d.numero, d.machineId, d.produit, d.quantitePrevue, d.tempsCycleS ?? null, d.dateDebut ?? null, d.dateFin ?? null],
)).rows[0].id;

async function update(id, data) {
  const sets = []; const params = [id];
  for (const [k, col] of Object.entries(MAP)) {
    if (data[k] !== undefined) { params.push(data[k]); sets.push(`${col} = $${params.length}`); }
  }
  return (await query(`UPDATE ordres_fabrication SET ${sets.join(', ')} WHERE id = $1 RETURNING id`, params)).rows[0];
}

module.exports = { list, findById, create, update };
