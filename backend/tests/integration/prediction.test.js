// US-22 : service de prédiction du backend avec un faux service d'IA (le vrai est testé dans ml/tests).
const url = process.env.TEST_DATABASE_URL;
Object.assign(process.env, {
  DATABASE_URL: url || 'postgres://invalide@localhost:1/x',
  JWT_ACCESS_SECRET: 'a'.repeat(40), JWT_REFRESH_SECRET: 'b'.repeat(40), NODE_ENV: 'test',
  ML_URL: 'http://ia.test:8000', ML_API_KEY: 'cle-ia', PREDICTION_PAS_S: '3600',
});
const test = require('node:test');
const assert = require('node:assert/strict');

if (!url || !/_test\b|test$/.test(url)) {
  test('intégration prédiction', { skip: 'TEST_DATABASE_URL absente' }, () => {});
  return;
}

const { pool, query } = require('../../src/config/db');
const migrate = require('../../src/db/migrate');
const prediction = require('../../src/services/prediction.service');
const { bus } = require('../../src/realtime/eventBus');

test.before(async () => {
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate();
  const { rows: [m] } = await query("INSERT INTO machines (code, nom) VALUES ('P01', 'Pompe') RETURNING id");
  const { rows: [c] } = await query("INSERT INTO capteurs (identifiant, machine_id, type, unite) VALUES ('P01-VIB', $1, 'VIBRATION', 'imp/s') RETURNING id", [m.id]);
  // 3 mesures dans le pas le plus récent (moyenne 20), 1 il y a 5 h, 1 trop ancienne (9 jours)
  const now = Date.now();
  for (const [minAgo, v] of [[5, 10], [20, 20], [40, 30], [5 * 60 + 10, 7], [9 * 24 * 60, 99]]) {
    await query('INSERT INTO mesures (capteur_id, valeur, horodatage) VALUES ($1, $2, $3)', [c.id, v, new Date(now - minAgo * 60e3)]);
  }
});
test.after(() => pool.end());

test('US-22 : fenêtre envoyée au modèle, résultat stocké, alerte au passage en risque élevé', async () => {
  const appels = [];
  let niveau = 'MOYEN';
  prediction.setFetch(async (u, opts) => {
    appels.push({ u, opts, body: JSON.parse(opts.body) });
    return { ok: true, json: async () => JSON.parse(opts.body).map((d) => ({
      machineId: d.machineId, probabilite: niveau === 'ELEVE' ? 0.31 : 0.12, niveau, donneesSuffisantes: true,
      facteurs: [{ canal: 'vibration', ecart: 2.4, libelle: 'Vibration 2.4 écart(s)-type(s) au-dessus de l’habitude' }],
      modele: 'test-1' })) };
  });
  const evts = [];
  const on = (e) => evts.push(e);
  bus.on('event', on);

  await prediction.executer();
  const { u, opts, body: [req] } = appels[0];
  assert.equal(u, 'http://ia.test:8000/predict/batch');
  assert.equal(opts.headers['X-API-Key'], 'cle-ia');
  assert.equal(req.series.vibration.length, 192);
  assert.equal(req.series.vibration[191], 20);   // moyenne du pas le plus récent
  assert.equal(req.series.vibration[186], 7);    // il y a 5 h
  assert.equal(req.series.vibration.filter((v) => v !== null).length, 2); // la mesure de 9 jours est hors fenêtre
  assert.ok(evts.some((e) => e.type === 'prediction.maj'));
  assert.ok(!evts.some((e) => e.type === 'prediction.risque'));

  niveau = 'ELEVE';
  await prediction.executer();
  await prediction.executer(); // reste ELEVE : pas de seconde notification
  bus.off('event', on);
  assert.equal(evts.filter((e) => e.type === 'prediction.risque').length, 1);

  const [last] = await prediction.derniere();
  assert.equal(last.niveau, 'ELEVE');
  assert.equal(last.facteurs[0].canal, 'vibration');
  assert.equal((await prediction.historique(last.machineId)).length, 3);
});

test('US-22 : service d’IA injoignable -> aucune prédiction inventée', async () => {
  prediction.setFetch(async () => { throw new Error('ECONNREFUSED'); });
  const avant = (await query('SELECT COUNT(*)::int n FROM predictions')).rows[0].n;
  assert.deepEqual(await prediction.executer(), []);
  assert.equal((await query('SELECT COUNT(*)::int n FROM predictions')).rows[0].n, avant);
});
