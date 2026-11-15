const { query } = require('../../config/db');

// Colonnes renvoyées au front : jamais le hash du mot de passe
const COLS = `id, nom, prenom, email, telephone, role, statut, specialite, disponible,
  doit_changer_mdp AS "doitChangerMotDePasse", date_desactivation AS "dateDesactivation", created_at AS "createdAt"`;

async function list(role, { recherche, statut, disponible }) {
  const where = ['role = $1'];
  const params = [role];
  if (recherche) { params.push(`%${recherche}%`); where.push(`(nom ILIKE $${params.length} OR prenom ILIKE $${params.length} OR email ILIKE $${params.length})`); }
  if (statut) { params.push(statut); where.push(`statut = $${params.length}`); }
  if (disponible !== undefined) { params.push(disponible); where.push(`disponible = $${params.length}`); }
  const sql = `SELECT ${COLS},
      (SELECT COUNT(*)::int FROM interventions i WHERE i.technicien_id = u.id AND i.statut IN ('AFFECTEE','EN_COURS')) AS "interventionsEnCours"
    FROM utilisateurs u WHERE ${where.join(' AND ')} ORDER BY nom, prenom`;
  return (await query(sql, params)).rows;
}

const findById = async (id, role) =>
  (await query(`SELECT ${COLS} FROM utilisateurs WHERE id = $1 AND role = $2`, [id, role])).rows[0];

async function create(data, role, hash, creePar) {
  const { rows } = await query(
    `INSERT INTO utilisateurs (nom, prenom, email, telephone, specialite, role, mot_de_passe_hash, cree_par)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING ${COLS}`,
    [data.nom, data.prenom, data.email, data.telephone || null, data.specialite || null, role, hash, creePar],
  );
  return rows[0];
}

const FIELD_MAP = { nom: 'nom', prenom: 'prenom', email: 'email', telephone: 'telephone', specialite: 'specialite', disponible: 'disponible' };

async function update(id, role, data) {
  const sets = []; const params = [id, role];
  for (const [k, col] of Object.entries(FIELD_MAP)) {
    if (data[k] !== undefined) { params.push(data[k]); sets.push(`${col} = $${params.length}`); }
  }
  const { rows } = await query(
    `UPDATE utilisateurs SET ${sets.join(', ')}, updated_at = NOW() WHERE id = $1 AND role = $2 RETURNING ${COLS}`, params,
  );
  return rows[0];
}

async function setStatut(id, role, statut) {
  const { rows } = await query(
    `UPDATE utilisateurs SET statut = $3::statut_compte,
       date_desactivation = CASE WHEN $3::statut_compte = 'DESACTIVE' THEN NOW() ELSE NULL END, updated_at = NOW()
     WHERE id = $1 AND role = $2 RETURNING ${COLS}`, [id, role, statut],
  );
  if (rows[0] && statut === 'DESACTIVE') {
    await query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE utilisateur_id = $1 AND revoked_at IS NULL', [id]);
  }
  return rows[0];
}

// US-35 : nouveau mot de passe provisoire, à changer à la prochaine connexion ; toutes les sessions sont fermées
async function reinitialiserMotDePasse(id, role, hash) {
  const { rows } = await query(
    `UPDATE utilisateurs SET mot_de_passe_hash = $3, doit_changer_mdp = TRUE, updated_at = NOW()
     WHERE id = $1 AND role = $2 RETURNING ${COLS}`, [id, role, hash],
  );
  if (rows[0]) await query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE utilisateur_id = $1 AND revoked_at IS NULL', [id]);
  return rows[0];
}

module.exports = { list, findById, create, update, setStatut, reinitialiserMotDePasse };
