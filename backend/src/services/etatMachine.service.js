// Calcule l'état d'une machine (vert / orange / rouge / maintenance / gris) à partir des règles métier :
//  EN_MAINTENANCE : une intervention est en cours
//  PANNE          : une intervention curative est ouverte, ou une alerte CRITIQUE n'est pas clôturée
//  ALERTE         : une alerte de niveau ALERTE n'est pas clôturée
//  SANS_DONNEES   : aucun message reçu d'un capteur actif dans le délai d'inactivité (heure de réception)
//                   (la carte ESP32 déconnectée — Last Will "offline" — met ses capteurs hors ligne)
//  NORMAL         : sinon
const { query } = require('../config/db');
const env = require('../config/env');
const { publish } = require('../realtime/eventBus');

async function calculerEtat(machineId) {
  const { rows } = await query(
    `SELECT
       EXISTS (SELECT 1 FROM interventions WHERE machine_id = $1 AND statut = 'EN_COURS') AS en_cours,
       EXISTS (SELECT 1 FROM interventions WHERE machine_id = $1 AND type = 'CURATIVE'
               AND statut IN ('A_AFFECTER','AFFECTEE')) AS curative_ouverte,
       EXISTS (SELECT 1 FROM alertes WHERE machine_id = $1 AND statut <> 'CLOTUREE' AND niveau = 'CRITIQUE') AS critique,
       EXISTS (SELECT 1 FROM alertes WHERE machine_id = $1 AND statut <> 'CLOTUREE' AND niveau = 'ALERTE') AS alerte,
       EXISTS (SELECT 1 FROM capteurs WHERE machine_id = $1 AND actif AND en_ligne
               AND derniere_reception_at > NOW() - make_interval(secs => $2)) AS donnees`,
    [machineId, env.CAPTEUR_DELAI_INACTIVITE_S],
  );
  const s = rows[0];
  if (s.en_cours) return 'EN_MAINTENANCE';
  if (s.curative_ouverte || s.critique) return 'PANNE';
  if (s.alerte) return 'ALERTE';
  if (!s.donnees) return 'SANS_DONNEES';
  return 'NORMAL';
}

// Recalcule et enregistre l'état ; publie un événement temps réel s'il a changé
async function mettreAJour(machineId) {
  const etat = await calculerEtat(machineId);
  const { rows } = await query(
    `UPDATE machines SET etat = $2, updated_at = NOW()
     WHERE id = $1 AND etat IS DISTINCT FROM $2 RETURNING id, code, etat`,
    [machineId, etat],
  );
  if (rows[0]) publish('machine.etat', { machineId: rows[0].id, code: rows[0].code, etat: rows[0].etat });
  return etat;
}

module.exports = { calculerEtat, mettreAJour };
