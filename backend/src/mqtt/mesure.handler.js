// Traitement d'un message MQTT de mesures : validation -> stockage -> comparaison aux seuils -> alerte -> état machine
const { z } = require('zod');
const { query } = require('../config/db');
const alertesRepo = require('../modules/alertes/alertes.repository');
const etatMachine = require('../services/etatMachine.service');
const { publish } = require('../realtime/eventBus');
const notifications = require('../modules/notifications/notifications.service');
const logger = require('../utils/logger');
const { PLAGES, CHAMPS_MQTT: CHAMPS } = require('../utils/mesures');

// null = lecture du capteur échouée côté ESP32 (ex. DHT22 qui ne répond pas) : la valeur est ignorée.
// Les champs supplémentaires envoyés par la carte (seq, uptime_s, alertes_locales...) sont ignorés.
const valeur = z.number().finite().nullable().optional();
const payloadSchema = z.object({
  courant: valeur,
  vibration: valeur,
  temperature: valeur,
  humidite: valeur,
  ts: z.union([z.number().int().positive(), z.string().datetime({ offset: true })]).optional(),
}).refine((p) => Object.keys(CHAMPS).some((champ) => p[champ] != null), 'Aucune mesure dans le message');

// Horodatage de l'ESP32 accepté s'il est cohérent avec l'horloge du serveur, sinon heure du serveur.
// Une mesure peut légitimement être ancienne : la carte renvoie après une coupure Wi-Fi les messages gardés
// en mémoire (US-45 : 180 messages x 5 s = 15 min, vidés 20 par cycle). Au-delà de RETARD_MAX_MS, ce n'est
// plus un renvoi mais une horloge décalée (carte ou PC sans NTP) : on garde l'heure du serveur pour que
// toutes les dates de la base (mesures, alertes, interventions) restent cohérentes entre elles.
const AVANCE_MAX_MS = 5 * 60 * 1000;
const RETARD_MAX_MS = 20 * 60 * 1000;
function resolveDate(ts, maintenant = Date.now()) {
  if (ts === undefined) return new Date(maintenant);
  const d = typeof ts === 'number' ? new Date(ts < 1e12 ? ts * 1000 : ts) : new Date(ts);
  const ecart = maintenant - d.getTime();
  if (Number.isNaN(d.getTime()) || ecart < -AVANCE_MAX_MS || ecart > RETARD_MAX_MS) return new Date(maintenant);
  return d;
}

// Avertissement (au plus toutes les 10 min par machine) quand l'horloge de la carte et celle du serveur divergent
const derniersAvertissements = new Map();
function signalerDecalage(codeMachine, ts, horodatage) {
  if (ts === undefined) return;
  const d = typeof ts === 'number' ? new Date(ts < 1e12 ? ts * 1000 : ts) : new Date(ts);
  if (Number.isNaN(d.getTime()) || d.getTime() === horodatage.getTime()) return;
  const dernier = derniersAvertissements.get(codeMachine) || 0;
  if (Date.now() - dernier < 10 * 60 * 1000) return;
  derniersAvertissements.set(codeMachine, Date.now());
  const minutes = Math.round((horodatage.getTime() - d.getTime()) / 60000);
  logger.warn(`Horloge de la carte ${codeMachine} décalée de ${minutes} min par rapport au serveur : heure du serveur utilisée. `
    + "Vérifiez l'heure du PC (timedatectl : NTP actif) et la synchronisation NTP de la carte.");
}

function niveauPour(valeur, seuil) {
  if (!seuil) return null;
  if (valeur >= seuil.seuil_critique) return { niveau: 'CRITIQUE', seuil: seuil.seuil_critique };
  if (valeur >= seuil.seuil_alerte) return { niveau: 'ALERTE', seuil: seuil.seuil_alerte };
  return null;
}

// US-39 : valeur corrigée = gain x valeur brute + offset (arrondie pour éviter les artefacts flottants)
function appliquerCalibration(brute, capteur) {
  const gain = capteur.calibration_gain ?? 1;
  const offset = capteur.calibration_offset ?? 0;
  if (gain === 1 && offset === 0) return brute;
  return Math.round((gain * brute + offset) * 1e4) / 1e4;
}

let retourEnLigne = new Set(); // machines dont un capteur hors ligne vient de renvoyer une mesure

async function traiterValeur(machine, type, brute, horodatage) {
  const { rows: [capteur] } = await query(
    `SELECT id, identifiant, unite, calibration_gain, calibration_offset FROM capteurs
     WHERE machine_id = $1 AND type = $2 AND actif ORDER BY id DESC LIMIT 1`,
    [machine.id, type],
  );
  if (!capteur) {
    logger.warn(`Mesure ${type} reçue pour ${machine.code} mais aucun capteur actif de ce type n'est déclaré`);
    return;
  }
  const valeur = appliquerCalibration(brute, capteur);

  const [min, max] = PLAGES[type];
  if (valeur < min || valeur > max) {
    logger.warn(`Mesure invalide ignorée : ${capteur.identifiant} = ${valeur} (plage ${min}-${max})`);
    publish('capteur.mesure_invalide', { machineId: machine.id, capteurId: capteur.id, valeur }, { roles: ['RESPONSABLE'] });
    return;
  }

  const { rows: [mesure] } = await query(
    'INSERT INTO mesures (capteur_id, valeur, horodatage) VALUES ($1, $2, $3) RETURNING id',
    [capteur.id, valeur, horodatage],
  );
  // en_ligne / derniere_reception_at : présence vue par le serveur (heure de réception)
  const { rows: [etat] } = await query(
    `UPDATE capteurs c SET derniere_mesure_at = GREATEST(COALESCE(c.derniere_mesure_at, $2), $2),
       derniere_reception_at = NOW(), en_ligne = TRUE
     FROM (SELECT en_ligne FROM capteurs WHERE id = $1) avant
     WHERE c.id = $1 RETURNING avant.en_ligne AS "etaitEnLigne"`,
    [capteur.id, horodatage],
  );
  if (etat && !etat.etaitEnLigne) retourEnLigne.add(machine.id);
  publish('mesure.recue', {
    machineId: machine.id, codeMachine: machine.code, capteurId: capteur.id, type, valeur, unite: capteur.unite, horodatage,
  });

  const { rows: [seuil] } = await query('SELECT seuil_alerte, seuil_critique FROM seuils WHERE machine_id = $1 AND type_mesure = $2', [machine.id, type]);
  const depassement = niveauPour(valeur, seuil);
  if (!depassement) return;

  const ouverte = await alertesRepo.findOpenByCapteur(capteur.id);
  if (!ouverte) {
    const created = await alertesRepo.create({
      machineId: machine.id, capteurId: capteur.id, mesureId: mesure.id, mesureAt: horodatage, niveau: depassement.niveau, valeur, seuil: depassement.seuil,
    });
    if (created) {
      const alerte = await alertesRepo.findById(created.id);
      logger.warn(`ALERTE ${alerte.niveau} sur ${machine.code} : ${type} = ${valeur} (seuil ${depassement.seuil}, détectée ${alerte.delaiDetectionS} s après la mesure)`);
      // US-01 / US-02 : le technicien est aussi prévenu ; US-38 : canaux APP et EMAIL
      publish('alerte.creee', { ...alerte, notifier: await notifications.notifierApp(alerte) }, { roles: ['RESPONSABLE', 'DIRECTEUR', 'TECHNICIEN'] });
      notifications.alerteSansAttendre(alerte);
    }
  } else if (ouverte.niveau === 'ALERTE' && depassement.niveau === 'CRITIQUE') {
    await alertesRepo.escalate(ouverte.id, mesure.id, valeur, depassement.seuil);
    const alerte = await alertesRepo.findById(ouverte.id);
    publish('alerte.maj', { ...alerte, notifier: await notifications.notifierApp(alerte) }, { roles: ['RESPONSABLE', 'DIRECTEUR', 'TECHNICIEN'] });
    notifications.alerteSansAttendre(alerte); // l'escalade en CRITIQUE peut déclencher l'e-mail
  }
}

async function handleMesures(codeMachine, buffer) {
  let payload;
  try {
    payload = payloadSchema.parse(JSON.parse(buffer.toString('utf8')));
  } catch (e) {
    logger.warn(`Message MQTT rejeté (${codeMachine}) : format invalide`);
    return;
  }

  const { rows: [machine] } = await query('SELECT id, code FROM machines WHERE code = $1', [codeMachine]);
  if (!machine) {
    logger.warn(`Mesures reçues pour une machine inconnue : ${codeMachine}`);
    return;
  }

  const horodatage = resolveDate(payload.ts);
  signalerDecalage(machine.code, payload.ts, horodatage);
  retourEnLigne = new Set();
  for (const [champ, type] of Object.entries(CHAMPS)) {
    if (payload[champ] != null) await traiterValeur(machine, type, payload[champ], horodatage);
  }
  // US-21 : retour en ligne annoncé une fois par machine (les applications mettent à jour l'état)
  if (retourEnLigne.has(machine.id)) {
    publish('capteur.etat', { machineId: machine.id, codeMachine: machine.code, enLigne: true }, { roles: ['RESPONSABLE', 'DIRECTEUR', 'TECHNICIEN'] });
  }
  await etatMachine.mettreAJour(machine.id);
}

// Statut de connexion de l'ESP32 (message "online" à la connexion, "offline" via Last Will)
async function handleStatut(codeMachine, buffer) {
  const statut = buffer.toString('utf8').trim().toLowerCase();
  if (statut !== 'online' && statut !== 'offline') return;
  const { rows } = await query(
    `UPDATE capteurs c SET en_ligne = $2 FROM machines m
     WHERE c.machine_id = m.id AND m.code = $1 RETURNING m.id AS machine_id`,
    [codeMachine, statut === 'online'],
  );
  if (!rows.length) return;
  publish('capteur.etat', { machineId: rows[0].machine_id, codeMachine, enLigne: statut === 'online' }, { roles: ['RESPONSABLE', 'DIRECTEUR', 'TECHNICIEN'] });
  // US-21 : la machine passe tout de suite en « Sans données » quand sa carte se déconnecte
  await etatMachine.mettreAJour(rows[0].machine_id);
  if (statut === 'offline') logger.warn(`ESP32 de la machine ${codeMachine} déconnecté`);
}

module.exports = { handleMesures, handleStatut, appliquerCalibration, niveauPour, resolveDate, payloadSchema };
