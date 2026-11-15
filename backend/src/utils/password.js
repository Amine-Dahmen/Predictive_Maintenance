const bcrypt = require('bcryptjs');
const crypto = require('crypto');

const ROUNDS = 12;

const hashPassword = (plain) => bcrypt.hash(plain, ROUNDS);
const verifyPassword = (plain, hash) => bcrypt.compare(plain, hash);

// Mot de passe provisoire lisible pour les nouveaux comptes (12 caractères).
function generateTemporaryPassword() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  const bytes = crypto.randomBytes(12);
  let out = '';
  for (const b of bytes) out += alphabet[b % alphabet.length];
  return `${out}!7`;
}

module.exports = { hashPassword, verifyPassword, generateTemporaryPassword };
