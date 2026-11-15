// US-21 / US-45 : présence des capteurs et horloge de la carte décalée (cas réel du 13/11/2026 : PC en
// avance d'une heure, sans NTP -> chaque mesure de la carte semblait vieille d'une heure, les capteurs
// passaient « hors ligne » toutes les 15 s puis « en ligne » au message suivant).
const url = process.env.TEST_DATABASE_URL;
Object.assign(process.env, {
  DATABASE_URL: url || 'postgres://invalide@localhost:1/x',
  JWT_ACCESS_SECRET: 'a'.repeat(40), JWT_REFRESH_SECRET: 'b'.repeat(40), NODE_ENV: 'test', CAPTEUR_DELAI_INACTIVITE_S: '60',
});
const test = require('node:test');
const assert = require('node:assert/strict');

if (!url || !/_test\b|test$/.test(url)) {
  test('intégration présence', { skip: 'TEST_DATABASE_URL absente' }, () => {});
  return;
}

const { pool, query } = require('../../src/config/db');
const migrate = require('../../src/db/migrate');
const { handleMesures } = require('../../src/mqtt/mesure.handler');
const surveillance = require('../../src/services/surveillanceCapteurs.service');
const { bus } = require('../../src/realtime/eventBus');

let machineId;
const envoyer = (p) => handleMesures('P01', Buffer.from(JSON.stringify(p)));
const evenements = async (fn) => {
  const evts = [];
  const on = (e) => { if (e.type === 'capteur.etat') evts.push(e.data); };
  bus.on('event', on);
  try { await fn(); } finally { bus.off('event', on); }
  return evts;
};

test.before(async () => {
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate();
  machineId = (await query("INSERT INTO machines (code, nom) VALUES ('P01', 'Pompe') RETURNING id")).rows[0].id;
  for (const type of ['COURANT', 'VIBRATION', 'TEMPERATURE', 'HUMIDITE']) {
    await query("INSERT INTO capteurs (identifiant, machine_id, type, unite) VALUES ($1, $2, $3, 'u')", [`P01-${type}`, machineId, type]);
  }
});
test.after(() => pool.end());

test('horloge de la carte en retard d’une heure : mesures datées à l’heure du serveur, capteurs en ligne', async () => {
  const uneHeure = 3600;
  const ts = Math.floor(Date.now() / 1000) - uneHeure;
  await envoyer({ courant: 1, vibration: 2, temperature: 25, humidite: 50, ts });
  const { rows: [m] } = await query('SELECT EXTRACT(EPOCH FROM (NOW() - MAX(horodatage)))::int AS age FROM mesures');
  assert.ok(m.age < 5, `mesure datée ${m.age} s dans le passé`);
  // la surveillance ne les déclare pas hors ligne : ils viennent d'être reçus
  assert.deepEqual(await evenements(() => surveillance.verifier()), []);
  const { rows: [etat] } = await query('SELECT etat FROM machines WHERE id = $1', [machineId]);
  assert.notEqual(etat.etat, 'SANS_DONNEES');
});

test('renvoi après coupure Wi-Fi : l’horodatage d’origine est gardé, la présence suit la réception', async () => {
  const ilYa10min = Math.floor(Date.now() / 1000) - 600;
  await envoyer({ courant: 1.5, ts: ilYa10min });
  const { rows: [m] } = await query(
    `SELECT EXTRACT(EPOCH FROM me.horodatage)::bigint AS t FROM mesures me JOIN capteurs c ON c.id = me.capteur_id
     WHERE c.type = 'COURANT' ORDER BY me.id DESC LIMIT 1`,
  );
  assert.equal(Number(m.t), ilYa10min);
  assert.deepEqual(await evenements(() => surveillance.verifier()), []);
});

test('carte silencieuse : un seul événement hors ligne pour la machine, puis un seul retour en ligne', async () => {
  await query("UPDATE capteurs SET derniere_reception_at = NOW() - INTERVAL '2 minutes'");
  const horsLigne = await evenements(() => surveillance.verifier());
  assert.equal(horsLigne.length, 1);
  assert.equal(horsLigne[0].enLigne, false);
  assert.equal(horsLigne[0].capteurs.length, 4);
  assert.deepEqual(await evenements(() => surveillance.verifier()), []); // pas de répétition
  const { rows: [etat] } = await query('SELECT etat FROM machines WHERE id = $1', [machineId]);
  assert.equal(etat.etat, 'SANS_DONNEES');

  const retour = await evenements(() => envoyer({ courant: 1, vibration: 2, temperature: 25, humidite: 50 }));
  assert.deepEqual(retour.map((e) => e.enLigne), [true]);
  assert.deepEqual(await evenements(() => envoyer({ courant: 1, vibration: 2 })), []); // déjà en ligne
});
