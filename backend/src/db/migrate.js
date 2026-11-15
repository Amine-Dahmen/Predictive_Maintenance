// Exécute dans l'ordre les fichiers SQL de src/db/migrations qui n'ont pas encore été appliqués.
// Usage : npm run db:migrate
const fs = require('fs');
const path = require('path');
const { pool } = require('../config/db');
const logger = require('../utils/logger');

async function migrate() {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    nom VARCHAR(200) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`);

  const dir = path.join(__dirname, 'migrations');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  const { rows } = await pool.query('SELECT nom FROM schema_migrations');
  const done = new Set(rows.map((r) => r.nom));

  for (const file of files) {
    if (done.has(file)) continue;
    const sql = fs.readFileSync(path.join(dir, file), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations(nom) VALUES ($1) ON CONFLICT DO NOTHING', [file]);
      await client.query('COMMIT');
      logger.info(`Migration appliquée : ${file}`);
    } catch (err) {
      await client.query('ROLLBACK');
      throw new Error(`Échec de la migration ${file} : ${err.message}`);
    } finally {
      client.release();
    }
  }
  logger.info('Base de données à jour.');
}

if (require.main === module) {
  migrate()
    .catch((err) => { logger.error(err.message); process.exitCode = 1; })
    .finally(() => pool.end());
}

module.exports = migrate;
