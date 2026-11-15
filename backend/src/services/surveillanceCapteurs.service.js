// Tâche périodique : détecte les capteurs qui n'envoient plus de mesures (PB-16).
// Un capteur dont aucun message n'a été REÇU depuis CAPTEUR_DELAI_INACTIVITE_S (horloge du serveur) passe
// hors ligne et sa machine est recalculée (elle passe en SANS_DONNEES, jamais en NORMAL).
// Un seul événement par machine, pas un par capteur.
const env = require('../config/env');
const { query } = require('../config/db');
const etatMachine = require('./etatMachine.service');
const { publish } = require('../realtime/eventBus');
const logger = require('../utils/logger');

let timer = null;

async function verifier() {
  const { rows } = await query(
    `UPDATE capteurs SET en_ligne = FALSE
     WHERE actif AND en_ligne AND (derniere_reception_at IS NULL OR derniere_reception_at < NOW() - make_interval(secs => $1))
     RETURNING id, identifiant, machine_id`,
    [env.CAPTEUR_DELAI_INACTIVITE_S],
  );
  const machines = new Set();
  for (const c of rows) {
    logger.warn(`Capteur inactif : ${c.identifiant}`);
    machines.add(c.machine_id);
  }
  for (const machineId of machines) {
    const capteurs = rows.filter((c) => c.machine_id === machineId).map((c) => c.identifiant);
    publish('capteur.etat', { machineId, capteurs, enLigne: false }, { roles: ['RESPONSABLE', 'DIRECTEUR', 'TECHNICIEN'] });
  }
  // Machines dont les données sont devenues trop anciennes
  const stale = await query(
    `SELECT id FROM machines m WHERE etat IN ('NORMAL','ALERTE') AND NOT EXISTS (
       SELECT 1 FROM capteurs c WHERE c.machine_id = m.id AND c.actif AND c.derniere_reception_at > NOW() - make_interval(secs => $1))`,
    [env.CAPTEUR_DELAI_INACTIVITE_S],
  );
  stale.rows.forEach((r) => machines.add(r.id));
  for (const id of machines) await etatMachine.mettreAJour(id);
}

module.exports = {
  start(intervalMs = 15000) {
    timer = setInterval(() => verifier().catch((e) => logger.error('Surveillance capteurs :', e.message)), intervalMs);
  },
  stop() { if (timer) clearInterval(timer); },
  verifier,
};
