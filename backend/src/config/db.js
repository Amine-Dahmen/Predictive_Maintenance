// Pool de connexions PostgreSQL partagé par toute l'application.
// Toutes les requêtes passent par query() avec des paramètres ($1, $2...) : jamais de concaténation SQL.
const { Pool } = require('pg');
const env = require('./env');
const logger = require('../utils/logger');

const pool = new Pool({
  ...(env.DATABASE_URL
    ? { connectionString: env.DATABASE_URL }
    : {
        host: env.DB_HOST,
        port: env.DB_PORT,
        database: env.DB_NAME,
        user: env.DB_USER,
        password: env.DB_PASSWORD,
      }),
  max: 10,
  idleTimeoutMillis: 30000,
});

pool.on('error', (err) => logger.error('Erreur PostgreSQL inattendue', err));

const query = (text, params) => pool.query(text, params);

// Exécute fn(client) dans une transaction (BEGIN / COMMIT / ROLLBACK automatique).
async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { pool, query, withTransaction };
