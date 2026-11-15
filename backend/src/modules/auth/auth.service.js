const repo = require('./auth.repository');
const { withTransaction } = require('../../config/db');
const { verifyPassword, hashPassword } = require('../../utils/password');
const { signAccessToken, generateRefreshToken, hashToken } = require('../../utils/tokens');
const AppError = require('../../utils/AppError');
const logger = require('../../utils/logger');

// Hash factice pour que la durée de réponse soit identique quand l'e-mail n'existe pas
// (empêche de deviner quels e-mails ont un compte)
const DUMMY_HASH = require('bcryptjs').hashSync('mot-de-passe-factice', 12);

const publicUser = (u) => ({
  id: u.id, nom: u.nom, prenom: u.prenom, email: u.email, telephone: u.telephone || null,
  role: u.role, statut: u.statut,
  doitChangerMotDePasse: u.doit_changer_mdp,
});

async function updateProfile(userId, telephone) {
  const user = await repo.updateTelephone(userId, telephone);
  return publicUser(user);
}

async function issueTokens(user, db) {
  const accessToken = signAccessToken(user);
  const { token, tokenHash, expiresAt } = generateRefreshToken();
  await repo.saveRefreshToken(user.id, tokenHash, expiresAt, db);
  return { accessToken, refreshToken: token, tokenType: 'Bearer' };
}

async function login(email, motDePasse) {
  const user = await repo.findUserByEmail(email);
  const ok = await verifyPassword(motDePasse, user ? user.mot_de_passe_hash : DUMMY_HASH);
  if (!user || !ok || user.statut !== 'ACTIF') {
    logger.warn(`Échec de connexion pour ${email}`);
    throw new AppError(401, 'E-mail ou mot de passe incorrect', 'IDENTIFIANTS_INVALIDES');
  }
  const tokens = await issueTokens(user);
  return { ...tokens, utilisateur: publicUser(user) };
}

// Rotation : chaque refresh token ne sert qu'une fois. S'il est réutilisé, on suppose un vol
// et on révoque toutes les sessions de l'utilisateur.
async function refresh(refreshToken) {
  const result = await withTransaction(async (db) => {
    const stored = await repo.findRefreshToken(hashToken(refreshToken), db);
    if (!stored) throw new AppError(401, 'Session invalide', 'SESSION_INVALIDE');

    // Jeton déjà utilisé : on sort de la transaction SANS erreur pour que la révocation ci-dessous soit enregistrée
    if (stored.revoked_at) return { reutilisation: stored.utilisateur_id };
    if (new Date(stored.expires_at) < new Date()) throw new AppError(401, 'Session expirée', 'SESSION_EXPIREE');

    const user = await repo.findUserById(stored.utilisateur_id, db);
    if (!user || user.statut !== 'ACTIF') throw new AppError(401, 'Compte désactivé', 'SESSION_INVALIDE');

    await repo.revokeRefreshToken(stored.id, db);
    const tokens = await issueTokens(user, db);
    return { ...tokens, utilisateur: publicUser(user) };
  });

  if (result.reutilisation) {
    await repo.revokeAllForUser(result.reutilisation);
    logger.warn(`Réutilisation d'un refresh token révoqué (utilisateur ${result.reutilisation}) : toutes les sessions sont fermées`);
    throw new AppError(401, 'Session invalide, reconnectez-vous', 'SESSION_INVALIDE');
  }
  return result;
}

async function logout(refreshToken) {
  await repo.revokeByHash(hashToken(refreshToken));
}

async function changePassword(userId, ancien, nouveau) {
  const user = await repo.findUserById(userId);
  if (!(await verifyPassword(ancien, user.mot_de_passe_hash))) {
    throw new AppError(400, 'Ancien mot de passe incorrect', 'MOT_DE_PASSE_INCORRECT');
  }
  const hash = await hashPassword(nouveau);
  return withTransaction(async (db) => {
    await repo.updatePassword(userId, hash, db);
    await repo.revokeAllForUser(userId, db); // déconnecte les autres appareils
    const tokens = await issueTokens({ ...user, doit_changer_mdp: false }, db);
    return { ...tokens, utilisateur: publicUser({ ...user, doit_changer_mdp: false }) };
  });
}

module.exports = { login, refresh, logout, changePassword, updateProfile, publicUser };
