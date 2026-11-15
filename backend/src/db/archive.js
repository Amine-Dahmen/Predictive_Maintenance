// Archivage manuel des anciennes mesures (US-40). Usage : npm run db:archive [-- <jours>]
const { pool } = require('../config/db');
const env = require('../config/env');
const logger = require('../utils/logger');
const { archiver } = require('../services/archivage.service');

const jours = process.argv[2] !== undefined ? Number(process.argv[2]) : env.MESURES_RETENTION_JOURS;
archiver(jours)
  .then((r) => logger.info(`Archivage terminé : ${r.archivees} mesure(s), ${r.heures} heure(s) résumée(s)`))
  .catch((e) => { logger.error(e.message); process.exitCode = 1; })
  .finally(() => pool.end());
