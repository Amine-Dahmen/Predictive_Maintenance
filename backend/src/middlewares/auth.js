// Middlewares de sécurité :
//  authenticate : vérifie le JWT puis recharge l'utilisateur en base (un compte désactivé est bloqué immédiatement)
//  authorize    : contrôle d'accès par rôle (RBAC)
const { verifyAccessToken } = require('../utils/tokens');
const { query } = require('../config/db');
const AppError = require('../utils/AppError');

function extractToken(req) {
  const header = req.headers.authorization || '';
  if (header.startsWith('Bearer ')) return header.slice(7);
  // Exception pour le flux temps réel (EventSource ne peut pas envoyer d'en-tête)
  if (req.allowQueryToken && typeof req.query.token === 'string') return req.query.token;
  return null;
}

/**
 * @param {object}  [options]
 * @param {boolean} [options.allowPasswordChangePending=false] autorise un compte qui doit encore changer son mot de passe
 */
function authenticate(options = {}) {
  return async (req, res, next) => {
    try {
      const token = extractToken(req);
      if (!token) throw AppError.unauthorized();

      let payload;
      try {
        payload = verifyAccessToken(token);
      } catch (e) {
        const msg = e.name === 'TokenExpiredError' ? 'Jeton expiré' : 'Jeton invalide';
        throw new AppError(401, msg, e.name === 'TokenExpiredError' ? 'JETON_EXPIRE' : 'JETON_INVALIDE');
      }

      const { rows } = await query(
        'SELECT id, nom, prenom, email, telephone, role, statut, doit_changer_mdp FROM utilisateurs WHERE id = $1',
        [Number(payload.sub)],
      );
      const user = rows[0];
      if (!user || user.statut !== 'ACTIF') throw AppError.unauthorized('Compte inexistant ou désactivé');
      if (user.doit_changer_mdp && !options.allowPasswordChangePending) {
        throw new AppError(403, 'Vous devez changer votre mot de passe provisoire', 'CHANGEMENT_MDP_REQUIS');
      }

      req.user = user;
      next();
    } catch (err) {
      next(err);
    }
  };
}

function authorize(...roles) {
  return (req, res, next) => {
    if (!req.user) return next(AppError.unauthorized());
    if (!roles.includes(req.user.role)) return next(AppError.forbidden('Votre rôle ne permet pas cette action'));
    next();
  };
}

const ROLES = Object.freeze({ DIRECTEUR: 'DIRECTEUR', RESPONSABLE: 'RESPONSABLE', TECHNICIEN: 'TECHNICIEN' });

module.exports = { authenticate, authorize, ROLES };
