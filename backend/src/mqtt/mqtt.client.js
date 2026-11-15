// Client MQTT du backend : s'abonne aux mesures des ESP32 et les transmet au handler.
// Les messages sont traités un par un (file d'attente) pour garder l'ordre et ne pas saturer PostgreSQL.
const mqtt = require('mqtt');
const env = require('../config/env');
const topics = require('./topics');
const { handleMesures, handleStatut } = require('./mesure.handler');
const seuilsPublisher = require('./seuils.publisher');
const firmware = require('../modules/firmware/firmware.service');
const logger = require('../utils/logger');

let client = null;
let chain = Promise.resolve();

function connect() {
  client = mqtt.connect(env.MQTT_URL, {
    clientId: env.MQTT_CLIENT_ID,
    username: env.MQTT_USERNAME,
    password: env.MQTT_PASSWORD,
    clean: false,             // session persistante : les messages QoS 1 reçus pendant une coupure sont livrés
    reconnectPeriod: 5000,
    connectTimeout: 10000,
    will: { topic: topics.backendStatut, payload: 'offline', qos: 1, retain: true },
  });

  client.on('connect', () => {
    logger.info(`MQTT connecté à ${env.MQTT_URL}`);
    client.publish(topics.backendStatut, 'online', { qos: 1, retain: true });
    seuilsPublisher.init((topic, payload) => client.publish(topic, payload, { qos: 1, retain: true }));
    seuilsPublisher.publierTous().catch((e) => logger.error('Envoi des seuils aux cartes impossible :', e.message));
    firmware.init((code, payload) => client.publish(topics.ota(code), payload, { qos: 1, retain: false }));
    client.subscribe(topics.subscriptions, { qos: 1 }, (err) => {
      if (err) logger.error('Abonnement MQTT impossible', err.message);
      else logger.info(`Abonné à : ${topics.subscriptions.join(', ')}`);
    });
  });

  client.on('message', (topic, payload) => {
    const t = topics.parse(topic);
    if (!t) return;
    if (payload.length > 4096) { logger.warn(`Message trop volumineux ignoré sur ${topic}`); return; }
    chain = chain
      .then(() => {
        if (t.kind === 'mesures') return handleMesures(t.codeMachine, payload);
        if (t.kind === 'ota') return firmware.statutCarte(t.codeMachine, payload);
        return handleStatut(t.codeMachine, payload);
      })
      .catch((err) => logger.error(`Erreur de traitement MQTT (${topic}) :`, err.message));
  });

  client.on('reconnect', () => logger.warn('MQTT : reconnexion...'));
  client.on('error', (err) => logger.error('MQTT :', err.message));
  client.on('offline', () => logger.warn('MQTT : hors ligne'));
  return client;
}

const isConnected = () => Boolean(client && client.connected);

async function disconnect() {
  if (!client) return;
  await new Promise((resolve) => client.publish(topics.backendStatut, 'offline', { qos: 1, retain: true }, () => resolve()));
  await client.endAsync();
}

module.exports = { connect, isConnected, disconnect };
