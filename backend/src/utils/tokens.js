// Gestion des jetons :
//  - access token  : JWT signé (HS256), courte durée (15 min), envoyé dans "Authorization: Bearer <jwt>"
//  - refresh token : chaîne aléatoire opaque, longue durée (7 j), stockée HACHÉE en base, rotation à chaque usage
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const env = require('../config/env');

const ISSUER = 'maintenance-iot-api';

function signAccessToken(user) {
  return jwt.sign({ role: user.role }, env.JWT_ACCESS_SECRET, {
    subject: String(user.id),
    expiresIn: env.JWT_ACCESS_EXPIRES_IN,
    issuer: ISSUER,
    algorithm: 'HS256',
  });
}

function verifyAccessToken(token) {
  // algorithms est fixé pour empêcher l'attaque "alg: none" ou le changement d'algorithme
  return jwt.verify(token, env.JWT_ACCESS_SECRET, { issuer: ISSUER, algorithms: ['HS256'] });
}

function generateRefreshToken() {
  const token = crypto.randomBytes(48).toString('base64url');
  const expiresAt = new Date(Date.now() + env.JWT_REFRESH_EXPIRES_DAYS * 24 * 3600 * 1000);
  return { token, tokenHash: hashToken(token), expiresAt };
}

// HMAC du refresh token : une fuite de la base ne permet pas de réutiliser les jetons
function hashToken(token) {
  return crypto.createHmac('sha256', env.JWT_REFRESH_SECRET).update(token).digest('hex');
}

module.exports = { signAccessToken, verifyAccessToken, generateRefreshToken, hashToken };
