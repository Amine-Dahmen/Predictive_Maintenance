// Tests d'intégration Release 3 : API HTTP + traitement MQTT + PostgreSQL réel.
// La base TEST_DATABASE_URL est VIDÉE puis recréée par les migrations. Ne jamais pointer sur la base de dev.
//   TEST_DATABASE_URL=postgres://maint:maint_password@localhost:5432/maintenance_iot_test npm run test:integration
const os = require('os');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const url = process.env.TEST_DATABASE_URL;
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'predimaint-it-'));
Object.assign(process.env, {
  DATABASE_URL: url || 'postgres://invalide@localhost:1/x',
  JWT_ACCESS_SECRET: 'a'.repeat(40), JWT_REFRESH_SECRET: 'b'.repeat(40), NODE_ENV: 'test',
  UPLOADS_DIR: path.join(tmp, 'uploads'), FIRMWARE_DIR: path.join(tmp, 'firmware'),
  PUBLIC_BASE_URL: 'http://192.168.1.10:3000', MESURES_RETENTION_JOURS: '90', SMTP_HOST: '',
});

const test = require('node:test');
const assert = require('node:assert/strict');

if (!url || !/_test\b|test$/.test(url)) {
  test('intégration Release 3', { skip: 'TEST_DATABASE_URL absente (ou ne se termine pas par _test)' }, () => {});
  return;
}

const { pool, query } = require('../../src/config/db');
const migrate = require('../../src/db/migrate');
const app = require('../../src/app');
const { hashPassword } = require('../../src/utils/password');
const { handleMesures } = require('../../src/mqtt/mesure.handler');
const firmware = require('../../src/modules/firmware/firmware.service');
const { archiver } = require('../../src/services/archivage.service');
const { bus } = require('../../src/realtime/eventBus');

let server; let base;
const tokens = {};
const MDP = 'MotDePasse123';

async function api(role, method, p, body, headers = {}) {
  const isForm = body instanceof FormData;
  const res = await fetch(`${base}/api${p}`, {
    method,
    headers: { ...(tokens[role] ? { Authorization: `Bearer ${tokens[role]}` } : {}), ...(body && !isForm ? { 'Content-Type': 'application/json' } : {}), ...headers },
    body: body ? (isForm ? body : JSON.stringify(body)) : undefined,
  });
  const type = res.headers.get('content-type') || '';
  const data = type.includes('json') ? await res.json() : Buffer.from(await res.arrayBuffer());
  return { status: res.status, data, headers: res.headers };
}

async function creerUtilisateur(email, role) {
  const { rows } = await query(
    `INSERT INTO utilisateurs (nom, prenom, email, mot_de_passe_hash, role, doit_changer_mdp, specialite)
     VALUES ('Test', $2::text, $1, $3, $2::role_utilisateur, FALSE, 'Électrique') RETURNING id`, [email, role, await hashPassword(MDP)],
  );
  return rows[0].id;
}
const login = async (email) => (await api(null, 'POST', '/auth/login', { email, motDePasse: MDP })).data.accessToken;
const mesure = (code, p) => handleMesures(code, Buffer.from(JSON.stringify({ ts: Date.now(), ...p })));
const ids = {};

test.before(async () => {
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate();
  ids.directeur = await creerUtilisateur('dir@test.local', 'DIRECTEUR');
  ids.responsable = await creerUtilisateur('resp@test.local', 'RESPONSABLE');
  ids.technicien = await creerUtilisateur('tech@test.local', 'TECHNICIEN');
  server = app.listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
  tokens.DIRECTEUR = await login('dir@test.local');
  tokens.RESPONSABLE = await login('resp@test.local');
  tokens.TECHNICIEN = await login('tech@test.local');
  // deux machines équipées de la carte PrédiMaint
  for (const code of ['M01', 'M02']) {
    const r = await api('RESPONSABLE', 'POST', '/machines', { code, nom: `Machine ${code}`, kitPredimaint: true });
    assert.equal(r.status, 201);
    ids[code] = r.data.id;
  }
});

test.after(async () => {
  server.close();
  await pool.end();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('US-31 fausse alerte : clôturée, marquée, exclue du comptage par machine', async () => {
  await mesure('M01', { temperature: 50 }); // seuil d'alerte 45
  const { data: [alerte] } = await api('RESPONSABLE', 'GET', `/alertes?machineId=${ids.M01}&statut=OUVERTE`);
  assert.equal(alerte.niveau, 'ALERTE');
  assert.equal((await api('TECHNICIEN', 'PATCH', `/alertes/${alerte.id}/fausse-alerte`, { commentaire: 'Porte du four ouverte' })).status, 403);
  const r = await api('RESPONSABLE', 'PATCH', `/alertes/${alerte.id}/fausse-alerte`, { commentaire: 'Porte du four ouverte' });
  assert.equal(r.status, 200);
  assert.equal(r.data.fausseAlerte, true);
  assert.equal(r.data.statut, 'CLOTUREE');
  const par = (await api('RESPONSABLE', 'GET', '/alertes/par-machine')).data.find((m) => m.machineId === ids.M01);
  assert.equal(par.nbAlertes, 0);
  const histo = (await api('RESPONSABLE', 'GET', `/machines/${ids.M01}/historique`)).data;
  assert.equal(histo.find((h) => h.id === alerte.id && h.categorie === 'ALERTE').statut, 'FAUSSE_ALERTE');
  assert.equal((await api('RESPONSABLE', 'GET', '/alertes?fausseAlerte=true')).data.length, 1);
  // deuxième marquage refusé
  assert.equal((await api('RESPONSABLE', 'PATCH', `/alertes/${alerte.id}/fausse-alerte`, { commentaire: 'encore' })).status, 409);
});

test('US-39 calibration : appliquée aux nouvelles mesures, mise à zéro sur la valeur actuelle', async () => {
  const machine = (await api('TECHNICIEN', 'GET', `/machines/${ids.M01}`)).data;
  const courant = machine.capteurs.find((c) => c.type === 'COURANT');
  await mesure('M01', { courant: 0.42 }); // courant résiduel moteur à l'arrêt
  const zero = await api('TECHNICIEN', 'PATCH', `/capteurs/${courant.id}/calibration`, { valeurReference: 0 });
  assert.equal(zero.status, 200);
  assert.equal(zero.data.calibrationOffset, -0.42);
  await mesure('M01', { courant: 1.42 });
  const { data: [last] } = await api('TECHNICIEN', 'GET', `/machines/${ids.M01}/mesures?type=COURANT&limit=1`);
  assert.equal(last.valeur, 1);
  const gain = await api('RESPONSABLE', 'PATCH', `/capteurs/${courant.id}/calibration`, { gain: 2, offset: 0 });
  assert.equal(gain.data.calibrationGain, 2);
  assert.equal((await api('DIRECTEUR', 'PATCH', `/capteurs/${courant.id}/calibration`, { gain: 1 })).status, 403);
  await api('RESPONSABLE', 'PATCH', `/capteurs/${courant.id}/calibration`, { gain: 1, offset: 0 });
});

test('US-37 remplacement d’un capteur : ancien retiré avec son historique, mesures vers le nouveau', async () => {
  const machine = (await api('RESPONSABLE', 'GET', `/machines/${ids.M02}`)).data;
  const vib = machine.capteurs.find((c) => c.type === 'VIBRATION');
  await mesure('M02', { vibration: 30 }); // alerte ouverte sur l'ancien capteur
  const r = await api('RESPONSABLE', 'POST', `/capteurs/${vib.id}/remplacer`, {});
  assert.equal(r.status, 201);
  assert.equal(r.data.identifiant, 'M02-VIBRATION-R2');
  const apres = (await api('RESPONSABLE', 'GET', `/machines/${ids.M02}`)).data;
  const ancien = apres.capteurs.find((c) => c.id === vib.id);
  assert.equal(ancien.actif, false);
  assert.equal(ancien.remplacePar, r.data.id);
  assert.equal((await api('RESPONSABLE', 'GET', `/alertes?machineId=${ids.M02}&statut=OUVERTE`)).data.length, 0);
  await mesure('M02', { vibration: 5 });
  const { data: [last] } = await api('RESPONSABLE', 'GET', `/machines/${ids.M02}/mesures?type=VIBRATION&limit=1`);
  assert.equal(last.capteurId, r.data.id);
  assert.equal((await api('RESPONSABLE', 'POST', `/capteurs/${vib.id}/remplacer`, {})).status, 409);
  // un second remplacement génère -R3
  assert.equal((await api('RESPONSABLE', 'POST', `/capteurs/${r.data.id}/remplacer`, {})).data.identifiant, 'M02-VIBRATION-R3');
});

test('US-29 / US-34 / US-16 / US-33 : panne déclarée, coût des arrêts, fréquence et synthèse', async () => {
  assert.equal((await api('DIRECTEUR', 'PATCH', `/machines/${ids.M01}/cout`, { coutHoraireArret: 120 })).status, 200);
  const debut = new Date(Date.now() - 2 * 3600e3);
  assert.equal((await api('DIRECTEUR', 'POST', `/machines/${ids.M01}/pannes`, { description: 'Moteur bloqué' })).status, 403);
  assert.equal((await api('RESPONSABLE', 'POST', `/machines/${ids.M01}/pannes`, { description: 'Moteur bloqué', technicienId: ids.technicien })).status, 400);
  const p = await api('RESPONSABLE', 'POST', `/machines/${ids.M01}/pannes`, { description: 'Moteur bloqué', debutPanne: debut });
  assert.equal(p.status, 201);
  assert.equal(p.data.type, 'CURATIVE');
  assert.equal((await api('RESPONSABLE', 'GET', `/machines/${ids.M01}`)).data.etat, 'PANNE');
  // réparation : affectation, démarrage, compte rendu, clôture
  const id = p.data.id;
  await api('RESPONSABLE', 'PATCH', `/interventions/${id}/affecter`, { technicienId: ids.technicien, echeance: new Date(Date.now() + 86400e3) });
  await api('TECHNICIEN', 'PATCH', `/interventions/${id}/demarrer`);
  await api('TECHNICIEN', 'PUT', `/interventions/${id}/compte-rendu`, { diagnostic: 'Roulement grippé', actions: 'Roulement remplacé' });
  assert.equal((await api('TECHNICIEN', 'PATCH', `/interventions/${id}/cloturer`, { resultat: 'REMISE_EN_SERVICE' })).status, 200);

  const p2 = await api('RESPONSABLE', 'POST', `/machines/${ids.M02}/pannes`,
    { description: 'Fuite', technicienId: ids.technicien, echeance: new Date(Date.now() + 3600e3) });
  assert.equal(p2.status, 201);
  assert.equal(p2.data.statut, 'AFFECTEE');
  assert.equal(p2.data.technicienId, ids.technicien);
  assert.ok((await api('TECHNICIEN', 'GET', '/interventions')).data.some((x) => x.id === p2.data.id)); // visible dans « Mes interventions »
  await query("UPDATE interventions SET statut = 'ANNULEE' WHERE id = $1", [p2.data.id]);

  const ind = (await api('DIRECTEUR', 'GET', '/indicateurs')).data;
  const m1 = ind.machines.find((m) => m.machineId === ids.M01);
  assert.equal(m1.nbPannes, 1);
  assert.ok(Math.abs(m1.tempsArretH - 2) < 0.05, `temps d'arrêt ${m1.tempsArretH}`);
  assert.ok(Math.abs(m1.coutArret - 240) < 6, `coût ${m1.coutArret}`);
  assert.equal(ind.global.coutArret, m1.coutArret);
  assert.equal(m1.frequencePannes30j, 1); // 1 panne sur la période par défaut de 30 jours
  assert.ok(m1.dureeMoyennePanneH > 1.9);

  const series = (await api('DIRECTEUR', 'GET', '/indicateurs/pannes?grain=week')).data.series;
  assert.equal(series.reduce((a, s) => a + s.nbPannes, 0), 1);
  const dash = (await api('DIRECTEUR', 'GET', '/indicateurs/dashboard')).data;
  assert.equal(dash.topArrets[0].code, 'M01');
  assert.equal((await api('TECHNICIEN', 'GET', '/indicateurs/pannes')).status, 403);
});

test('extension US-26 : le technicien prend en charge une intervention non affectée, ou la panne qu’il déclare', async () => {
  // déclarée par un technicien : affectée d'office à lui (jamais orpheline)
  const p = await api('TECHNICIEN', 'POST', `/machines/${ids.M02}/pannes`, { description: 'Bruit anormal' });
  assert.equal(p.status, 201);
  assert.equal(p.data.statut, 'AFFECTEE');
  assert.equal(p.data.technicienId, ids.technicien);
  await query("UPDATE interventions SET statut = 'ANNULEE' WHERE id = $1", [p.data.id]);

  // déclarée par le responsable sans affectation : visible dans « À prendre »
  const r = await api('RESPONSABLE', 'POST', `/machines/${ids.M02}/pannes`, { description: 'Fuite d’huile' });
  assert.equal(r.data.statut, 'A_AFFECTER');
  const aPrendre = (await api('TECHNICIEN', 'GET', '/interventions?aPrendre=true')).data;
  assert.deepEqual(aPrendre.map((x) => x.id), [r.data.id]);
  assert.ok(!(await api('TECHNICIEN', 'GET', '/interventions')).data.some((x) => x.id === r.data.id)); // pas encore « mes interventions »
  assert.equal((await api('TECHNICIEN', 'GET', `/interventions/${r.data.id}`)).status, 200);           // détail consultable

  const pris = await api('TECHNICIEN', 'PATCH', `/interventions/${r.data.id}/prendre-en-charge`);
  assert.equal(pris.status, 200);
  assert.equal(pris.data.statut, 'AFFECTEE');
  assert.ok(pris.data.echeance);
  assert.equal((await api('TECHNICIEN', 'PATCH', `/interventions/${r.data.id}/prendre-en-charge`)).status, 409); // déjà prise
  assert.equal((await api('RESPONSABLE', 'PATCH', `/interventions/${r.data.id}/prendre-en-charge`)).status, 403);
  assert.equal((await api('TECHNICIEN', 'GET', '/interventions?aPrendre=true')).data.length, 0);
  await query("UPDATE interventions SET statut = 'ANNULEE' WHERE id = $1", [r.data.id]);
});

test('US-32 comparaison de machines', async () => {
  const r = await api('RESPONSABLE', 'GET', `/machines/comparaison?ids=${ids.M01},${ids.M02}&type=VIBRATION`);
  assert.equal(r.status, 200);
  assert.deepEqual(r.data.machines.map((m) => m.code), ['M01', 'M02']);
  const m2 = r.data.machines[1];
  assert.ok(m2.mesures[0].nb >= 2 && m2.mesures[0].maximum === 30);
  assert.ok(m2.serie.length >= 1);
  assert.equal(r.data.machines[0].indicateurs.nbPannes, 1);
  assert.equal((await api('RESPONSABLE', 'GET', `/machines/comparaison?ids=${ids.M01},9999`)).status, 404);
});

test('US-25 photos d’intervention : JPEG accepté, faux fichier refusé, accès contrôlé', async () => {
  const { data: [i] } = await api('RESPONSABLE', 'GET', '/interventions?statut=CLOTUREE');
  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), crypto.randomBytes(500)]);
  const form = new FormData();
  form.append('photo', new Blob([jpeg], { type: 'image/jpeg' }), 'avant.jpg');
  form.append('legende', 'Roulement usé');
  const up = await api('TECHNICIEN', 'POST', `/interventions/${i.id}/photos`, form);
  assert.equal(up.status, 201, JSON.stringify(up.data));
  assert.equal(up.data.typeMime, 'image/jpeg');

  const faux = new FormData();
  faux.append('photo', new Blob(['<html><script>alert(1)</script>'], { type: 'image/jpeg' }), 'x.jpg');
  assert.equal((await api('TECHNICIEN', 'POST', `/interventions/${i.id}/photos`, faux)).status, 400);
  const gros = new FormData();
  gros.append('photo', new Blob([Buffer.concat([jpeg, Buffer.alloc(6 * 1024 * 1024)])], { type: 'image/jpeg' }), 'g.jpg');
  assert.equal((await api('TECHNICIEN', 'POST', `/interventions/${i.id}/photos`, gros)).status, 400);

  const file = await api('DIRECTEUR', 'GET', `/interventions/${i.id}/photos/${up.data.id}/fichier`);
  assert.equal(file.status, 200);
  assert.ok(file.data.equals(jpeg));
  assert.equal(file.headers.get('content-type'), 'image/jpeg');
  assert.equal((await api(null, 'GET', `/interventions/${i.id}/photos/${up.data.id}/fichier`)).status, 401);
  assert.equal((await api('RESPONSABLE', 'GET', `/interventions/${i.id}`)).data.photos.length, 1);
  // un autre technicien ne voit pas l'intervention
  await creerUtilisateur('tech2@test.local', 'TECHNICIEN');
  tokens.TECH2 = await login('tech2@test.local');
  assert.equal((await api('TECH2', 'GET', `/interventions/${i.id}/photos/${up.data.id}/fichier`)).status, 404);
  assert.equal((await api('TECHNICIEN', 'DELETE', `/interventions/${i.id}/photos/${up.data.id}`)).status, 204);
});

test('US-35 / US-36 : réinitialisation du mot de passe et désactivation ferment les sessions', async () => {
  const r = await api('RESPONSABLE', 'POST', `/techniciens/${ids.technicien}/reinitialiser-mot-de-passe`);
  assert.equal(r.status, 200);
  assert.match(r.data.motDePasseProvisoire, /.{12,}/);
  assert.equal(r.data.doitChangerMotDePasse, true);
  // l'ancien mot de passe ne marche plus, le provisoire oui (avec changement obligatoire)
  assert.equal((await api(null, 'POST', '/auth/login', { email: 'tech@test.local', motDePasse: MDP })).status, 401);
  const l = await api(null, 'POST', '/auth/login', { email: 'tech@test.local', motDePasse: r.data.motDePasseProvisoire });
  assert.equal(l.data.utilisateur.doitChangerMotDePasse, true);
  assert.equal((await api('DIRECTEUR', 'POST', `/techniciens/${ids.technicien}/reinitialiser-mot-de-passe`)).status, 403);
  assert.equal((await api('DIRECTEUR', 'POST', `/responsables/${ids.responsable}/reinitialiser-mot-de-passe`)).status, 200);
  tokens.RESPONSABLE = null;
  await query('UPDATE utilisateurs SET doit_changer_mdp = FALSE, mot_de_passe_hash = $2 WHERE id = $1', [ids.responsable, await hashPassword(MDP)]);
  tokens.RESPONSABLE = await login('resp@test.local');

  // US-36 : le flux temps réel ouvert est fermé à la désactivation
  const tech2 = (await query("SELECT id FROM utilisateurs WHERE email = 'tech2@test.local'")).rows[0].id;
  const ctrl = new AbortController();
  const stream = await fetch(`${base}/api/stream?token=${tokens.TECH2}`, { signal: ctrl.signal });
  const reader = stream.body.getReader();
  await reader.read(); // événement « connecte »
  await api('RESPONSABLE', 'PATCH', `/techniciens/${tech2}/statut`, { statut: 'DESACTIVE' });
  let texte = ''; let fini = false;
  const limite = setTimeout(() => ctrl.abort(), 3000);
  while (!fini) { const { value, done } = await reader.read(); fini = done; if (value) texte += Buffer.from(value).toString(); }
  clearTimeout(limite);
  assert.match(texte, /session\.revoquee/);
  assert.equal((await api('TECH2', 'GET', '/machines')).status, 401);
});

test('US-38 canaux de notification : e-mail activé au niveau critique, champ notifier dans le flux', async () => {
  const canaux = (await api('DIRECTEUR', 'GET', '/notifications/canaux')).data;
  assert.deepEqual(canaux.map((c) => c.canal), ['APP', 'EMAIL']);
  assert.equal((await api('DIRECTEUR', 'PUT', '/notifications/canaux/EMAIL', { destinataires: 'pas-un-email' })).status, 400);
  const e = await api('DIRECTEUR', 'PUT', '/notifications/canaux/EMAIL', { actif: true, niveauMin: 'CRITIQUE', destinataires: 'chef@usine.local' });
  assert.equal(e.data.actif, true);
  await api('DIRECTEUR', 'PUT', '/notifications/canaux/APP', { niveauMin: 'CRITIQUE' });
  assert.equal((await api('RESPONSABLE', 'GET', '/notifications/canaux')).status, 403);

  const evts = [];
  const on = (evt) => evts.push(evt);
  bus.on('event', on);
  await mesure('M02', { humidite: 85 }); // ALERTE (80) : pas de notification avec APP >= CRITIQUE
  await mesure('M02', { humidite: 95 }); // escalade CRITIQUE (90)
  bus.off('event', on);
  assert.equal(evts.find((x) => x.type === 'alerte.creee').data.notifier, false);
  assert.equal(evts.find((x) => x.type === 'alerte.maj').data.notifier, true);
  await api('DIRECTEUR', 'PUT', '/notifications/canaux/APP', { niveauMin: 'ALERTE' });
});

test('US-17 rapport périodique : JSON, CSV et HTML échappé', async () => {
  await query("UPDATE machines SET nom = '<script>alert(1)</script>' WHERE id = $1", [ids.M02]);
  const j = await api('DIRECTEUR', 'GET', '/rapports/maintenance');
  assert.equal(j.status, 200);
  assert.equal(j.data.interventions.length, 1);
  assert.equal(j.data.alertes.fausses, 1);
  const csv = await api('DIRECTEUR', 'GET', '/rapports/maintenance?format=csv');
  assert.match(csv.headers.get('content-disposition'), /attachment; filename="rapport-maintenance-/);
  assert.match(csv.data.toString(), /M01;Machine M01;/);
  const html = (await api('RESPONSABLE', 'GET', '/rapports/maintenance?format=html')).data.toString();
  assert.ok(!html.includes('<script>alert(1)'));
  assert.ok(html.includes('&lt;script&gt;'));
  // mot de passe réinitialisé plus haut : l'ancien jeton d'accès exige d'abord le changement de mot de passe
  assert.equal((await api('TECHNICIEN', 'GET', '/rapports/maintenance')).status, 403);
  assert.equal((await api('DIRECTEUR', 'GET', '/rapports/maintenance?periode=mois-precedent')).status, 200);
});

test('US-40 archivage : mesures anciennes résumées par heure puis supprimées', async () => {
  const c = (await query("SELECT id FROM capteurs WHERE identifiant = 'M01-TEMPERATURE'")).rows[0].id;
  const vieux = new Date(Date.now() - 100 * 86400e3);
  vieux.setUTCMinutes(10, 0, 0);
  for (const [min, v] of [[10, 20], [20, 30], [30, 40]]) {
    await query('INSERT INTO mesures (capteur_id, valeur, horodatage) VALUES ($1, $2, $3)', [c, v, new Date(vieux.getTime() + (min - 10) * 60e3)]);
  }
  const r = await archiver(90);
  assert.equal(r.archivees, 3);
  const { rows: [h] } = await query('SELECT nb, moyenne, minimum, maximum FROM mesures_horaires WHERE capteur_id = $1', [c]);
  assert.deepEqual(h, { nb: 3, moyenne: 30, minimum: 20, maximum: 40 });
  // une mesure de la même heure archivée plus tard est fusionnée (moyenne pondérée)
  await query('INSERT INTO mesures (capteur_id, valeur, horodatage) VALUES ($1, 70, $2)', [c, vieux]);
  await archiver(90);
  const { rows: [h2] } = await query('SELECT nb, moyenne, maximum FROM mesures_horaires WHERE capteur_id = $1', [c]);
  assert.deepEqual(h2, { nb: 4, moyenne: 40, maximum: 70 });
  const recentes = (await query('SELECT COUNT(*)::int n FROM mesures WHERE capteur_id = $1', [c])).rows[0].n;
  assert.ok(recentes >= 1, 'les mesures récentes sont conservées');
  const archivees = await api('DIRECTEUR', 'GET', `/machines/${ids.M01}/mesures-horaires?type=TEMPERATURE&from=${new Date(Date.now() - 200 * 86400e3).toISOString()}`);
  assert.equal(archivees.data.length, 1);
});

test('US-46 mise à jour du firmware : ordre MQTT, téléchargement par jeton, suivi', async () => {
  const dir = path.join(process.env.FIRMWARE_DIR, '1.3.0');
  fs.mkdirSync(dir, { recursive: true });
  const contenu = Buffer.from('print("hello")\n');
  fs.writeFileSync(path.join(dir, 'main.py'), contenu);
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ version: '1.3.0', publieLe: new Date().toISOString(),
    fichiers: [{ nom: 'main.py', taille: contenu.length, sha256: crypto.createHash('sha256').update(contenu).digest('hex') }] }));

  assert.deepEqual((await api('RESPONSABLE', 'GET', '/firmware/versions')).data.map((v) => v.version), ['1.3.0']);
  const envoyes = [];
  firmware.init((code, payload) => envoyes.push({ code, ordre: JSON.parse(payload) }));
  assert.equal((await api('RESPONSABLE', 'POST', `/machines/${ids.M01}/firmware`, { version: '9.9.9' })).status, 400);
  const d = await api('RESPONSABLE', 'POST', `/machines/${ids.M01}/firmware`, { version: '1.3.0' });
  assert.equal(d.status, 201);
  assert.equal(envoyes[0].code, 'M01');
  const { ordre } = envoyes[0];
  assert.ok(ordre.url.startsWith('http://192.168.1.10:3000/api/firmware/telechargement/'));

  // la carte télécharge sans JWT, avec le jeton ; un autre fichier ou un faux jeton est refusé
  const chemin = new URL(ordre.url).pathname.replace(/^\/api/, '');
  const f = await api(null, 'GET', `${chemin}/main.py`);
  assert.equal(f.status, 200);
  assert.equal(f.data.toString(), contenu.toString());
  assert.equal((await api(null, 'GET', `${chemin}/credentials.py`)).status, 404);
  assert.equal((await api(null, 'GET', `/firmware/telechargement/${'0'.repeat(48)}/main.py`)).status, 404);

  const statut = (s) => firmware.statutCarte('M01', Buffer.from(JSON.stringify({ deploiement: ordre.deploiement, version: '1.3.0', ...s })));
  await statut({ statut: 'EN_COURS', message: 'telechargement' });
  await statut({ statut: 'REUSSI', message: 'ok' });
  const hist = (await api('RESPONSABLE', 'GET', `/machines/${ids.M01}/firmware`)).data;
  assert.equal(hist[0].statut, 'REUSSI');
  assert.equal((await api('RESPONSABLE', 'GET', `/machines/${ids.M01}`)).data.firmwareVersion, '1.3.0');
  // le jeton ne sert plus après la fin du déploiement
  assert.equal((await api(null, 'GET', `${chemin}/main.py`)).status, 404);
  assert.equal((await api('DIRECTEUR', 'POST', `/machines/${ids.M01}/firmware`, { version: '1.3.0' })).status, 403);
});
