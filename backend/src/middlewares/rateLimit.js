const rateLimit = require('express-rate-limit');

const message = (texte) => ({ erreur: { code: 'TROP_DE_REQUETES', message: texte } });

// Limite globale de l'API
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 300,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: message('Trop de requêtes, réessayez dans une minute'),
});

// Protection contre le brute force sur la connexion : 10 essais / 15 min par IP
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  message: message('Trop de tentatives de connexion, réessayez dans 15 minutes'),
});

module.exports = { apiLimiter, loginLimiter };
