const { query } = require('../../config/db');

const findUserByEmail = async (email) =>
  (await query('SELECT * FROM utilisateurs WHERE email = $1', [email])).rows[0];

const findUserById = async (id, db = { query }) =>
  (await db.query('SELECT * FROM utilisateurs WHERE id = $1', [id])).rows[0];

const saveRefreshToken = (userId, tokenHash, expiresAt, db = { query }) =>
  db.query('INSERT INTO refresh_tokens (utilisateur_id, token_hash, expires_at) VALUES ($1, $2, $3)', [userId, tokenHash, expiresAt]);

const findRefreshToken = async (tokenHash, db = { query }) =>
  (await db.query('SELECT * FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE', [tokenHash])).rows[0];

const revokeRefreshToken = (id, db = { query }) =>
  db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1 AND revoked_at IS NULL', [id]);

const revokeByHash = (tokenHash) =>
  query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL', [tokenHash]);

const revokeAllForUser = (userId, db = { query }) =>
  db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE utilisateur_id = $1 AND revoked_at IS NULL', [userId]);

const updatePassword = (userId, hash, db = { query }) =>
  db.query('UPDATE utilisateurs SET mot_de_passe_hash = $2, doit_changer_mdp = FALSE, updated_at = NOW() WHERE id = $1', [userId, hash]);

const updateTelephone = async (userId, telephone) =>
  (await query(
    'UPDATE utilisateurs SET telephone = $2, updated_at = NOW() WHERE id = $1 RETURNING id, nom, prenom, email, telephone, role, statut, doit_changer_mdp',
    [userId, telephone || null],
  )).rows[0];

module.exports = {
  findUserByEmail, findUserById, saveRefreshToken, findRefreshToken,
  revokeRefreshToken, revokeByHash, revokeAllForUser, updatePassword, updateTelephone,
};
