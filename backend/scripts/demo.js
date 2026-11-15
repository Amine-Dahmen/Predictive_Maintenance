// US-50 : maquette de démonstration (soutenance).
//
//   node scripts/demo.js historique [M01]   192 pas de mesures « normales » se terminant maintenant
//                                           (pas = PREDICTION_PAS_S) : le modèle d'IA a une référence tout de suite.
//                                           Niveau et bruit copiés des vraies mesures récentes de la machine
//                                           (sinon valeurs par défaut) ; seuls les pas sans mesure sont remplis.
//   node scripts/demo.js pannes [M01]       pannes et réparations passées (60 jours) pour les indicateurs du directeur
//   node scripts/demo.js nettoyer           supprime ce que ces commandes ont créé
//
// Puis, en direct : la vraie carte ESP32 (secouer la machine, chauffer le DHT22), ou
//   node scripts/simulateur-esp32.js M01 anomalie
// font monter les mesures -> alertes (seuils) puis risque de panne (IA) dans l'application.
const fs = require('fs');
const path = require('path');
const env = require('../src/config/env');
const { pool, query } = require('../src/config/db');

const MARQUE = '[démo]';
// Plages de mesures ajoutées par « historique », pour « nettoyer » (fichier local, ignoré par git)
const ETAT = path.join(__dirname, '..', '.demo-state.json');
const lireEtat = () => { try { return JSON.parse(fs.readFileSync(ETAT, 'utf8')); } catch { return { historiques: [] }; } };
const [cmd, code = 'M01'] = process.argv.slice(2);
const bruit = (amp) => (Math.random() - 0.5) * 2 * amp;
const NORMAL = { COURANT: [1.2, 0.08], VIBRATION: [2, 0.8], TEMPERATURE: [27, 0.4], HUMIDITE: [50, 1.5] };

async function machine() {
  const { rows: [m] } = await query('SELECT id FROM machines WHERE code = $1', [code]);
  if (!m) throw new Error(`Machine ${code} inconnue : créez-la d'abord (npm run db:seed crée M01)`);
  return m.id;
}

async function historique() {
  const id = await machine();
  const pas = env.PREDICTION_PAS_S;
  const fin = Date.now() - 2 * pas * 1000; // les 2 derniers pas restent aux mesures en direct
  let n = 0;
  for (const [type, [moy, sd]] of Object.entries(NORMAL)) {
    const { rows: [c] } = await query('SELECT id FROM capteurs WHERE machine_id = $1 AND type = $2 AND actif ORDER BY id DESC LIMIT 1', [id, type]);
    if (!c) continue;
    // « Normal » de CETTE machine : moyenne et écart-type de ses vraies mesures des dernières 24 h
    const { rows: [st] } = await query(
      `SELECT COUNT(*)::int n, AVG(valeur)::float m, STDDEV_SAMP(valeur)::float sd FROM mesures
       WHERE capteur_id = $1 AND horodatage > NOW() - INTERVAL '24 hours'`, [c.id],
    );
    const [m0, sd0] = st.n >= 30 ? [st.m, Math.max(st.sd || 0, sd * 0.1)] : [moy, sd];
    // pas qui ont déjà des mesures : laissés tels quels
    const { rows: occupes } = await query(
      `SELECT DISTINCT FLOOR(EXTRACT(EPOCH FROM ($2::timestamptz - horodatage)) / $3)::int AS k FROM mesures
       WHERE capteur_id = $1 AND horodatage > $2::timestamptz - make_interval(secs => $3 * 192) AND horodatage <= $2::timestamptz`,
      [c.id, new Date(fin), pas],
    );
    const pris = new Set(occupes.map((o) => o.k));
    const valeurs = []; const dates = [];
    for (let k = 190; k >= 0; k--) {
      if (pris.has(k)) continue;
      for (let j = 0; j < 3; j++) { // 3 mesures par pas
        valeurs.push(Number((m0 + bruit(sd0 * 1.7)).toFixed(3)));
        dates.push(new Date(fin - k * pas * 1000 - j * (pas * 1000) / 3));
      }
    }
    if (!valeurs.length) continue;
    await query(
      `INSERT INTO mesures (capteur_id, valeur, horodatage)
       SELECT $1, v, d FROM unnest($2::float8[], $3::timestamptz[]) AS t(v, d)`, [c.id, valeurs, dates],
    );
    const etat = lireEtat();
    etat.historiques.push({ capteurId: c.id, dates: dates.map((d) => d.toISOString()) });
    fs.writeFileSync(ETAT, JSON.stringify(etat, null, 2));
    n += valeurs.length;
  }
  console.log(`${n} mesures « normales » ajoutées sur ${code} dans les pas sans mesure (${Math.round((191 * pas) / 3600 * 10) / 10} h, pas de ${pas} s)`);
}

async function pannes() {
  const id = await machine();
  const jour = 86400e3;
  await query('UPDATE machines SET cout_horaire_arret = GREATEST(cout_horaire_arret, 150) WHERE id = $1', [id]);
  for (const [ilYa, duree, desc] of [[52, 3.5, 'Roulement du moteur grippé'], [31, 1.2, 'Courroie détendue'], [9, 5, 'Surchauffe du variateur']]) {
    const debut = new Date(Date.now() - ilYa * jour);
    await query(
      `INSERT INTO interventions (machine_id, type, priorite, statut, description, debut_panne, date_debut, date_fin, resultat, created_at)
       VALUES ($1, 'CURATIVE', 'URGENTE', 'CLOTUREE', $2, $3, $4, $5, 'REMISE_EN_SERVICE', $3)`,
      [id, `${MARQUE} ${desc}`, debut, new Date(debut.getTime() + 0.5 * 3600e3), new Date(debut.getTime() + duree * 3600e3)],
    );
  }
  console.log(`3 pannes passées ajoutées sur ${code} (coût horaire d'arrêt 150)`);
}

async function nettoyer() {
  const i = await query(`DELETE FROM interventions WHERE description LIKE $1`, [`${MARQUE}%`]);
  let m = 0;
  for (const h of lireEtat().historiques) {
    // uniquement les mesures écrites par « historique » (mêmes horodatages), jamais les vraies
    m += (await query('DELETE FROM mesures WHERE capteur_id = $1 AND horodatage = ANY($2::timestamptz[])', [h.capteurId, h.dates])).rowCount;
  }
  fs.rmSync(ETAT, { force: true });
  console.log(`${i.rowCount} intervention(s) et ${m} mesure(s) de démonstration supprimées`);
}

const actions = { historique, pannes, nettoyer };
if (!actions[cmd]) {
  console.log('Usage : node scripts/demo.js historique|pannes|nettoyer [code machine]');
  process.exit(1);
}
actions[cmd]().catch((e) => { console.error(e.message); process.exitCode = 1; }).finally(() => pool.end());
