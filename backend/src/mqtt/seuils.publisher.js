// US-11 : les seuils configurés dans l'application sont envoyés à la carte ESP32 de la machine
// sur {prefix}/machines/<code>/config (message retenu : la carte le reçoit à chaque connexion).
// La carte s'en sert pour allumer sa LED ; les alertes de référence restent celles du backend.
const { query } = require('../config/db');
const topics = require('./topics');
const { CHAMPS_MQTT } = require('../utils/mesures');
const logger = require('../utils/logger');

const CHAMP_PAR_TYPE = Object.fromEntries(Object.entries(CHAMPS_MQTT).map(([champ, type]) => [type, champ]));

// { seuils: { courant: { alerte, critique }, ... } } : noms de champs identiques au message de mesures
function construireConfig(seuils) {
  const config = { seuils: {} };
  for (const s of seuils) {
    const champ = CHAMP_PAR_TYPE[s.type_mesure];
    if (champ) config.seuils[champ] = { alerte: s.seuil_alerte, critique: s.seuil_critique };
  }
  return config;
}

let publishFn = null; // fourni par mqtt.client une fois connecté

function init(publish) {
  publishFn = publish;
}

async function publierSeuils(machineId) {
  if (!publishFn) return;
  const { rows: [machine] } = await query('SELECT code FROM machines WHERE id = $1', [machineId]);
  if (!machine) return;
  const { rows } = await query('SELECT type_mesure, seuil_alerte, seuil_critique FROM seuils WHERE machine_id = $1', [machineId]);
  publishFn(topics.config(machine.code), JSON.stringify(construireConfig(rows)));
}

async function publierTous() {
  const { rows } = await query('SELECT id FROM machines');
  for (const r of rows) await publierSeuils(r.id);
  logger.info(`Seuils envoyés aux cartes de ${rows.length} machine(s)`);
}

// Appel « fire and forget » depuis les services : une erreur MQTT ne doit pas faire échouer la requête HTTP
function publierSeuilsSansAttendre(machineId) {
  publierSeuils(machineId).catch((e) => logger.error('Envoi des seuils à la carte impossible :', e.message));
}

module.exports = { init, publierSeuils, publierTous, publierSeuilsSansAttendre, construireConfig };
