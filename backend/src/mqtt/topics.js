// Contrat des topics MQTT partagé avec l'équipe embarquée (voir docs/CONTRAT_MQTT.md)
//
//   ESP32 -> backend
//     {prefix}/machines/{codeMachine}/mesures   JSON {"courant": 12.4, "vibration": 3.2, "ts": 1734000000000}   QoS 1
//     {prefix}/machines/{codeMachine}/statut    "online" | "offline"  (retained, "offline" en Last Will)      QoS 1
//
//     {prefix}/machines/{codeMachine}/ota/statut JSON {"version", "deploiement", "statut", "message"}       QoS 1 (US-46)
//
//   backend -> ESP32
//     {prefix}/machines/{codeMachine}/config    JSON {"seuils": {"courant": {"alerte": 3, "critique": 4.5}, ...}}  (retained)
//     {prefix}/machines/{codeMachine}/ota       JSON ordre de mise à jour du firmware                            QoS 1 (US-46)
//
//   backend -> tout le monde
//     {prefix}/backend/statut                   "online" | "offline"  (retained)
const env = require('../config/env');

const P = env.MQTT_TOPIC_PREFIX;

module.exports = {
  subscriptions: [`${P}/machines/+/mesures`, `${P}/machines/+/statut`, `${P}/machines/+/ota/statut`],
  backendStatut: `${P}/backend/statut`,
  config: (codeMachine) => `${P}/machines/${codeMachine}/config`,
  ota: (codeMachine) => `${P}/machines/${codeMachine}/ota`,

  // Analyse un topic reçu et renvoie { kind, codeMachine } ou null
  parse(topic) {
    const parts = topic.split('/');
    if (parts.length === 5 && parts[0] === P && parts[1] === 'machines' && parts[3] === 'ota' && parts[4] === 'statut'
        && /^[A-Za-z0-9_-]{1,40}$/.test(parts[2])) return { kind: 'ota', codeMachine: parts[2] };
    if (parts.length !== 4 || parts[0] !== P || parts[1] !== 'machines') return null;
    const [, , codeMachine, kind] = parts;
    if (!/^[A-Za-z0-9_-]{1,40}$/.test(codeMachine)) return null;
    if (kind !== 'mesures' && kind !== 'statut') return null;
    return { kind, codeMachine };
  },
};
