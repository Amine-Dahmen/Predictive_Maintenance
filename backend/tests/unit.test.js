// Tests unitaires des règles métier (sans base de données ni broker). Lancer : npm test
process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'a'.repeat(40);
process.env.JWT_REFRESH_SECRET = 'b'.repeat(40);
process.env.NODE_ENV = 'test';

const test = require('node:test');
const assert = require('node:assert/strict');

const { niveauPour, resolveDate, payloadSchema } = require('../src/mqtt/mesure.handler');
const topics = require('../src/mqtt/topics');
const { calculer } = require('../src/modules/indicateurs/indicateurs.service');
const { signAccessToken, verifyAccessToken, hashToken, generateRefreshToken } = require('../src/utils/tokens');
const { password } = require('../src/utils/schemas');

test('seuils : normal, alerte, critique', () => {
  const s = { seuil_alerte: 4.5, seuil_critique: 7.1 };
  assert.equal(niveauPour(3, s), null);
  assert.deepEqual(niveauPour(5, s), { niveau: 'ALERTE', seuil: 4.5 });
  assert.deepEqual(niveauPour(7.1, s), { niveau: 'CRITIQUE', seuil: 7.1 });
  assert.equal(niveauPour(100, undefined), null);
});

test('topics MQTT : analyse et rejet des topics invalides', () => {
  assert.deepEqual(topics.parse('usine/machines/M01/mesures'), { kind: 'mesures', codeMachine: 'M01' });
  assert.deepEqual(topics.parse('usine/machines/M01/statut'), { kind: 'statut', codeMachine: 'M01' });
  assert.equal(topics.parse('usine/machines/M01/autre'), null);
  assert.equal(topics.parse('autre/machines/M01/mesures'), null);
  assert.equal(topics.parse('usine/machines/M 01/mesures'), null);
});

test('payload MQTT : validation', () => {
  assert.ok(payloadSchema.safeParse({ courant: 12.4, vibration: 3.1, ts: Date.now() }).success);
  assert.ok(payloadSchema.safeParse({ vibration: 3.1 }).success);
  assert.equal(payloadSchema.safeParse({}).success, false);
  assert.equal(payloadSchema.safeParse({ courant: 'douze' }).success, false);
});

test('payload MQTT de la carte PrédiMaint : 4 mesures, valeurs null et champs en plus', () => {
  const carte = { courant: 1.21, vibration: 3.4, temperature: 24.3, humidite: 51, ts: 1792745000, seq: 12, alertes_locales: [] };
  const r = payloadSchema.safeParse(carte);
  assert.ok(r.success);
  assert.equal(r.data.seq, undefined); // champs inconnus supprimés
  // DHT22 en échec : température et humidité null, le reste est traité
  assert.ok(payloadSchema.safeParse({ ...carte, temperature: null, humidite: null }).success);
  // aucune valeur exploitable
  assert.equal(payloadSchema.safeParse({ courant: null, vibration: null, temperature: null, humidite: null }).success, false);
  assert.equal(payloadSchema.safeParse({ temperature: '24' }).success, false);
});

test('types de mesure : unités, plages et seuils par défaut définis pour chaque type', () => {
  const { TYPES_MESURE, UNITES_PAR_DEFAUT, SEUILS_PAR_DEFAUT, PLAGES, CHAMPS_MQTT } = require('../src/utils/mesures');
  assert.deepEqual(Object.values(CHAMPS_MQTT).sort(), [...TYPES_MESURE].sort());
  for (const type of TYPES_MESURE) {
    assert.ok(UNITES_PAR_DEFAUT[type], `unité de ${type}`);
    const [min, max] = PLAGES[type];
    const [alerte, critique] = SEUILS_PAR_DEFAUT[type];
    assert.ok(alerte > 0 && critique > alerte && critique <= max && alerte >= min, `seuils de ${type}`);
  }
});

test('seuils envoyés à la carte : mêmes noms de champs que le message de mesures', () => {
  const { construireConfig } = require('../src/mqtt/seuils.publisher');
  assert.deepEqual(construireConfig([
    { type_mesure: 'COURANT', seuil_alerte: 3, seuil_critique: 4.5 },
    { type_mesure: 'HUMIDITE', seuil_alerte: 80, seuil_critique: 90 },
  ]), { seuils: { courant: { alerte: 3, critique: 4.5 }, humidite: { alerte: 80, critique: 90 } } });
  assert.deepEqual(construireConfig([]), { seuils: {} });
  assert.equal(topics.config('M01'), 'usine/machines/M01/config');
});

test('horodatage ESP32 : accepté si cohérent, sinon heure serveur', () => {
  const now = Date.now();
  assert.equal(resolveDate(now - 1000).getTime(), now - 1000);
  assert.equal(resolveDate(Math.floor((now - 2000) / 1000)).getTime(), Math.floor((now - 2000) / 1000) * 1000);
  assert.ok(Math.abs(resolveDate(now + 3600 * 1000).getTime() - now) < 1000); // futur -> heure serveur
  assert.ok(Math.abs(resolveDate(0 + 1).getTime() - now) < 1000);            // 1970 -> heure serveur
  // renvoi après coupure Wi-Fi (US-45, 15 min de mémoire tampon) : horodatage d'origine conservé
  assert.equal(resolveDate(now - 15 * 60e3, now).getTime(), now - 15 * 60e3);
  // horloge décalée d'une heure (PC ou carte sans NTP) : heure du serveur
  assert.equal(resolveDate(now - 3600e3, now).getTime(), now);
  assert.equal(resolveDate(now + 3600e3, now).getTime(), now);
});

test('indicateurs : MTBF, MTTR, disponibilité et TRS', () => {
  const periodeS = 100 * 3600; // 100 h
  const r = calculer({
    arret_s: 10 * 3600, nb_pannes: 3, mttr_s: 2 * 3600, nb_reparations: 3,
    produite: 900, rebutee: 45, temps_theorique_s: 900 * 300, of_incomplets: 0, of_termines: 2,
  }, periodeS);
  assert.equal(r.mtbfH, 30);           // (100 - 10) / 3
  assert.equal(r.mttrH, 2);
  assert.equal(r.disponibilite, 0.9);
  assert.equal(r.qualite, 0.95);
  assert.equal(r.performance, 0.8333); // 75 h théoriques / 90 h de fonctionnement
  assert.equal(r.trs, 0.7125);
  assert.equal(r.trsIncomplet, false);
});

test('indicateurs : données insuffisantes', () => {
  const r = calculer({ arret_s: 0, nb_pannes: 0, mttr_s: null, nb_reparations: 0, produite: 0, rebutee: 0, temps_theorique_s: null, of_incomplets: 0, of_termines: 0 }, 3600);
  assert.equal(r.mtbfH, null);
  assert.equal(r.mttrH, null);
  assert.equal(r.trs, null);
  assert.equal(r.trsIncomplet, true);
});

test('JWT : signature, vérification et refus d\'un jeton modifié', () => {
  const token = signAccessToken({ id: 7, role: 'RESPONSABLE' });
  const payload = verifyAccessToken(token);
  assert.equal(payload.sub, '7');
  assert.equal(payload.role, 'RESPONSABLE');
  const [h, p, s] = token.split('.');
  const forged = Buffer.from(JSON.stringify({ ...payload, role: 'DIRECTEUR' })).toString('base64url');
  assert.throws(() => verifyAccessToken(`${h}.${forged}.${s}`));
  const none = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  assert.throws(() => verifyAccessToken(`${none}.${p}.`));
});

test('refresh token : aléatoire et haché', () => {
  const a = generateRefreshToken(); const b = generateRefreshToken();
  assert.notEqual(a.token, b.token);
  assert.equal(a.tokenHash, hashToken(a.token));
  assert.equal(a.tokenHash.length, 64);
  assert.ok(a.expiresAt > new Date());
});

test('politique de mot de passe', () => {
  assert.equal(password.safeParse('court').success, false);
  assert.equal(password.safeParse('sansmajuscule1').success, false);
  assert.ok(password.safeParse('Maintenance2026').success);
});

// ---------- Release 3 ----------
const { appliquerCalibration } = require('../src/mqtt/mesure.handler');
const { calculerOffset } = require('../src/modules/machines/machines.service');
const rapports = require('../src/modules/rapports/rapports.service');
const { typeImage } = require('../src/modules/interventions/photos');
const notifications = require('../src/modules/notifications/notifications.service');
const machineSchemas = require('../src/modules/machines/machines.schemas');

test('US-39 calibration : gain et offset appliqués à la valeur brute', () => {
  assert.equal(appliquerCalibration(10, { calibration_gain: 1, calibration_offset: 0 }), 10);
  assert.equal(appliquerCalibration(10, { calibration_gain: 1.1, calibration_offset: -0.5 }), 10.5);
  assert.equal(appliquerCalibration(2.5, {}), 2.5);
});

test('US-39 mise à zéro : offset calculé pour que la valeur actuelle devienne la référence', () => {
  // ancien réglage gain 1, offset 0 : la valeur affichée 0.42 A doit devenir 0 A
  assert.equal(calculerOffset(0.42, 1, 0, 1, 0), -0.42);
  // valeur affichée 22 avec gain 2 / offset 2 (brute = 10) ; nouveau gain 1.5, référence 20 -> offset 5
  const offset = calculerOffset(22, 2, 2, 1.5, 20);
  assert.equal(offset, 5);
  assert.equal(appliquerCalibration(10, { calibration_gain: 1.5, calibration_offset: offset }), 20);
});

test('US-17 rapport : périodes prédéfinies et cellules CSV sûres', () => {
  const ref = new Date('2026-11-12T10:00:00Z'); // jeudi
  const mois = rapports.periodePredefinie('mois-precedent', ref);
  assert.equal(mois.from.toISOString(), '2026-10-01T00:00:00.000Z');
  assert.equal(mois.to.toISOString(), '2026-11-01T00:00:00.000Z');
  const sem = rapports.periodePredefinie('semaine-precedente', ref);
  assert.equal(sem.from.toISOString(), '2026-11-02T00:00:00.000Z'); // lundi précédent
  assert.equal(sem.to.toISOString(), '2026-11-09T00:00:00.000Z');
  assert.equal(rapports.csvCell('=HYPERLINK("x")'), `"'=HYPERLINK(""x"")"`); // injection de formule neutralisée
  assert.equal(rapports.csvCell('a;b'), '"a;b"');
  assert.equal(rapports.csvCell(null), '');
});

test('US-25 photos : type détecté sur le contenu du fichier', () => {
  assert.deepEqual(typeImage(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0])), { mime: 'image/jpeg', ext: 'jpg' });
  assert.deepEqual(typeImage(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0])), { mime: 'image/png', ext: 'png' });
  assert.equal(typeImage(Buffer.from('<svg onload=alert(1)>')), null);
  assert.equal(typeImage(Buffer.from('GIF89a......')), null);
});

test('US-38 canaux : niveau minimal et contenu de l’e-mail', () => {
  assert.ok(notifications.atteint('CRITIQUE', 'ALERTE'));
  assert.ok(notifications.atteint('CRITIQUE', 'CRITIQUE'));
  assert.ok(!notifications.atteint('ALERTE', 'CRITIQUE'));
  const { sujet, texte } = notifications.contenuEmail({ niveau: 'CRITIQUE', machineCode: 'M01', machineNom: 'Presse', typeMesure: 'COURANT', valeur: 5, unite: 'A', seuilDepasse: 4.5, createdAt: new Date() });
  assert.match(sujet, /CRITIQUE sur M01 : COURANT/);
  assert.match(texte, /COURANT = 5 A \(seuil 4.5\)/);
});

test('US-46 topics MQTT : statut OTA des cartes', () => {
  assert.deepEqual(topics.parse('usine/machines/M01/ota/statut'), { kind: 'ota', codeMachine: 'M01' });
  assert.equal(topics.parse('usine/machines/M01/ota'), null);
  assert.equal(topics.parse('usine/machines/M01/ota/autre'), null);
  assert.equal(topics.ota('M01'), 'usine/machines/M01/ota');
});

test('US-29 / US-32 : validation des déclarations de panne et des comparaisons', () => {
  assert.ok(machineSchemas.declarerPanne.safeParse({ description: 'Courroie cassée' }).success);
  assert.ok(!machineSchemas.declarerPanne.safeParse({ description: 'x', debutPanne: new Date(Date.now() + 3600e3) }).success);
  assert.deepEqual(machineSchemas.comparaison.parse({ ids: '3,1,3' }).ids, [3, 1]);
  assert.ok(!machineSchemas.comparaison.safeParse({ ids: '1' }).success);
  assert.ok(!machineSchemas.comparaison.safeParse({ ids: '1;DROP' }).success);
});

test('US-22 prédiction : séries de 192 pas, la plus récente en dernier, trous à null', () => {
  const { construireSeries, SPAN } = require('../src/services/prediction.service');
  const s = construireSeries([
    { type: 'COURANT', k: 0, v: 2.5 },        // pas le plus récent
    { type: 'COURANT', k: 191, v: 1.5 },      // pas le plus ancien
    { type: 'VIBRATION', k: 5, v: 12 },
    { type: 'HUMIDITE', k: 0, v: 50 },        // canal non utilisé par le modèle
    { type: 'COURANT', k: 192, v: 9 },        // hors fenêtre
  ]);
  assert.deepEqual(Object.keys(s), ['courant', 'vibration', 'temperature']);
  assert.equal(s.courant.length, SPAN);
  assert.equal(s.courant[SPAN - 1], 2.5);
  assert.equal(s.courant[0], 1.5);
  assert.equal(s.vibration[SPAN - 6], 12);
  assert.equal(s.temperature.every((v) => v === null), true);
  assert.equal(s.courant.filter((v) => v !== null).length, 2);
});
