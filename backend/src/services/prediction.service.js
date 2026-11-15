// US-22 (bonus) : probabilité de panne dans les 48 h, calculée par le service d'IA (dossier ml/).
//
// Toutes les PREDICTION_INTERVALLE_S, pour chaque machine :
//   1. moyennes des mesures par pas de PREDICTION_PAS_S (1 h en production) sur les 192 derniers pas
//      (24 pas récents + 168 pas de référence « normale » propre à la machine), canaux courant,
//      vibration et température ; un pas sans mesure vaut null
//   2. un seul appel POST {ML_URL}/predict/batch pour tout le parc
//   3. enregistrement (table predictions) et diffusion temps réel « prediction.maj » ;
//      passage au niveau ELEVE -> notification « prediction.risque » (responsables, techniciens)
// Le modèle et ses limites sont décrits dans ml/README.md. En démonstration, PREDICTION_PAS_S=60
// compresse le temps : 192 pas = 3 h 12 min de mesures au lieu de 8 jours.
const env = require('../config/env');
const { query } = require('../config/db');
const { publish } = require('../realtime/eventBus');
const logger = require('../utils/logger');

const SPAN = 192;
const CANAUX = { COURANT: 'courant', VIBRATION: 'vibration', TEMPERATURE: 'temperature' };

let timer = null;
let indisponibleSignale = false;
let fetchFn = (...args) => fetch(...args);

// Lignes {type, k, v} (k = 0 pour le pas le plus récent) -> {canal: [192 valeurs, plus anciennes d'abord]}
function construireSeries(lignes, span = SPAN) {
  const series = {};
  for (const canal of Object.values(CANAUX)) series[canal] = new Array(span).fill(null);
  for (const { type, k, v } of lignes) {
    const canal = CANAUX[type];
    if (canal && k >= 0 && k < span && v !== null) series[canal][span - 1 - k] = v;
  }
  return series;
}

async function seriesMachine(machineId, maintenant = new Date(), pasS = env.PREDICTION_PAS_S) {
  const { rows } = await query(
    `SELECT c.type, FLOOR(EXTRACT(EPOCH FROM ($2::timestamptz - me.horodatage)) / $3)::int AS k, AVG(me.valeur)::float AS v
     FROM mesures me JOIN capteurs c ON c.id = me.capteur_id
     WHERE c.machine_id = $1 AND c.type IN ('COURANT', 'VIBRATION', 'TEMPERATURE')
       AND me.horodatage > $2::timestamptz - make_interval(secs => $3 * $4) AND me.horodatage <= $2::timestamptz
     GROUP BY 1, 2`,
    [machineId, maintenant, pasS, SPAN],
  );
  return construireSeries(rows);
}

async function appelerModele(demandes) {
  const res = await fetchFn(`${env.ML_URL.replace(/\/$/, '')}/predict/batch`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(env.ML_API_KEY ? { 'X-API-Key': env.ML_API_KEY } : {}) },
    body: JSON.stringify(demandes),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) throw new Error(`service d'IA : HTTP ${res.status}`);
  return res.json();
}

const COLS = `p.machine_id AS "machineId", m.code, m.nom, p.probabilite, p.niveau, p.facteurs, p.modele, p.created_at AS "createdAt"`;

async function executer(maintenant = new Date()) {
  const { rows: machines } = await query('SELECT id, code FROM machines ORDER BY id');
  if (!machines.length) return [];
  const demandes = await Promise.all(machines.map(async (m) => ({ machineId: m.id, series: await seriesMachine(m.id, maintenant) })));
  let resultats;
  try {
    resultats = await appelerModele(demandes);
    if (indisponibleSignale) logger.info("Service d'IA de nouveau joignable");
    indisponibleSignale = false;
  } catch (e) {
    if (!indisponibleSignale) logger.warn(`Prédiction de panne indisponible (${env.ML_URL}) : ${e.message}`);
    indisponibleSignale = true;
    return [];
  }
  const sorties = [];
  for (const r of resultats) {
    const machine = machines.find((m) => m.id === r.machineId);
    if (!machine) continue;
    const { rows: [avant] } = await query(
      'SELECT niveau FROM predictions WHERE machine_id = $1 ORDER BY created_at DESC LIMIT 1', [machine.id],
    );
    const { rows: [p] } = await query(
      `INSERT INTO predictions AS p (machine_id, probabilite, niveau, facteurs, modele, created_at)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING ${COLS.replace(/, m\.code, m\.nom/, '')}`,
      [machine.id, r.probabilite, r.niveau, JSON.stringify(r.facteurs || []), r.modele, maintenant],
    );
    const evt = { ...p, code: machine.code };
    publish('prediction.maj', evt);
    if (r.niveau === 'ELEVE' && (!avant || avant.niveau !== 'ELEVE')) {
      logger.warn(`Risque de panne ÉLEVÉ sur ${machine.code} : ${Math.round(r.probabilite * 100)} % (${r.facteurs?.[0]?.libelle || ''})`);
      publish('prediction.risque', { ...evt, notifier: true }, { roles: ['RESPONSABLE', 'DIRECTEUR', 'TECHNICIEN'] });
    }
    sorties.push(evt);
  }
  // Historique conservé 30 jours
  await query("DELETE FROM predictions WHERE created_at < NOW() - INTERVAL '30 days'");
  return sorties;
}

const derniere = async () => (await query(
  `SELECT DISTINCT ON (p.machine_id) ${COLS} FROM predictions p JOIN machines m ON m.id = p.machine_id
   ORDER BY p.machine_id, p.created_at DESC`,
)).rows;

const historique = async (machineId, heures = 48) => (await query(
  `SELECT ${COLS} FROM predictions p JOIN machines m ON m.id = p.machine_id
   WHERE p.machine_id = $1 AND p.created_at > NOW() - make_interval(hours => $2) ORDER BY p.created_at`,
  [machineId, heures],
)).rows;

async function carteModele() {
  const res = await fetchFn(`${env.ML_URL.replace(/\/$/, '')}/modele`, {
    headers: env.ML_API_KEY ? { 'X-API-Key': env.ML_API_KEY } : {}, signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

module.exports = {
  SPAN, construireSeries, seriesMachine, executer, derniere, historique, carteModele,
  setFetch(fn) { fetchFn = fn; },
  start() {
    if (!env.PREDICTION_INTERVALLE_S) return;
    const run = () => executer().catch((e) => logger.error('Prédiction de panne :', e.message));
    setTimeout(run, 10000).unref();
    timer = setInterval(run, env.PREDICTION_INTERVALLE_S * 1000);
    timer.unref();
  },
  stop() { if (timer) clearInterval(timer); },
};
