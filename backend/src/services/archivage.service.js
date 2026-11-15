// US-40 : archivage des anciennes mesures.
// Les mesures brutes plus anciennes que MESURES_RETENTION_JOURS sont résumées par heure et par capteur
// (nombre, moyenne, minimum, maximum) dans mesures_horaires, puis supprimées. Les alertes gardent l'heure
// de leur mesure (mesure_at) ; leur lien mesure_id passe à NULL.
// Une heure déjà partiellement archivée est fusionnée (moyenne pondérée par le nombre de mesures).
const env = require('../config/env');
const { withTransaction } = require('../config/db');
const logger = require('../utils/logger');

let timer = null;

async function archiver(retentionJours = env.MESURES_RETENTION_JOURS, maintenant = new Date()) {
  if (!retentionJours) return { archivees: 0, heures: 0 };
  // Limite arrondie à l'heure : une heure n'est jamais coupée en deux entre brut et archive
  const limite = new Date(maintenant.getTime() - retentionJours * 86400000);
  limite.setUTCMinutes(0, 0, 0);
  return withTransaction(async (db) => {
    const resume = await db.query(
      `INSERT INTO mesures_horaires AS mh (capteur_id, heure, nb, moyenne, minimum, maximum)
       SELECT capteur_id, date_trunc('hour', horodatage), COUNT(*), AVG(valeur), MIN(valeur), MAX(valeur)
       FROM mesures WHERE horodatage < $1 GROUP BY 1, 2
       ON CONFLICT (capteur_id, heure) DO UPDATE SET
         moyenne = (mh.moyenne * mh.nb + EXCLUDED.moyenne * EXCLUDED.nb) / (mh.nb + EXCLUDED.nb),
         nb = mh.nb + EXCLUDED.nb,
         minimum = LEAST(mh.minimum, EXCLUDED.minimum),
         maximum = GREATEST(mh.maximum, EXCLUDED.maximum)`,
      [limite],
    );
    const suppr = await db.query('DELETE FROM mesures WHERE horodatage < $1', [limite]);
    if (suppr.rowCount) logger.info(`Archivage : ${suppr.rowCount} mesure(s) résumée(s) en ${resume.rowCount} heure(s) (avant ${limite.toISOString()})`);
    return { archivees: suppr.rowCount, heures: resume.rowCount, limite };
  });
}

module.exports = {
  archiver,
  // Une fois au démarrage puis toutes les 24 h
  start(intervalMs = 24 * 3600 * 1000) {
    const run = () => archiver().catch((e) => logger.error('Archivage des mesures :', e.message));
    setTimeout(run, 30000).unref();
    timer = setInterval(run, intervalMs);
    timer.unref();
  },
  stop() { if (timer) clearInterval(timer); },
};
