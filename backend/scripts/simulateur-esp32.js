// Simulateur d'ESP32 : publie les mêmes messages que la carte PrédiMaint (partie_embarque/) :
// courant (ACS712, A), vibration (SW-420, impulsions/s), température et humidité (DHT22).
// Permet au backend et au front d'avancer sans la carte.
//
// Usage :
//   node scripts/simulateur-esp32.js                 -> machine M01, valeurs normales
//   node scripts/simulateur-esp32.js M01 anomalie    -> vibration et température montent jusqu'à la panne
//
// Variables : MQTT_URL (défaut mqtt://localhost:1883), MQTT_TOPIC_PREFIX (défaut usine), ESP32_PASSWORD
require('dotenv').config();
const mqtt = require('mqtt');

const code = process.argv[2] || 'M01';
const mode = process.argv[3] || 'normal';
const prefix = process.env.MQTT_TOPIC_PREFIX || 'usine';
const base = `${prefix}/machines/${code}`;

const client = mqtt.connect(process.env.MQTT_URL || 'mqtt://localhost:1883', {
  clientId: `esp32-${code}-sim`,
  username: code,
  password: process.env.ESP32_PASSWORD || `esp32_${code}_pwd`,
  will: { topic: `${base}/statut`, payload: 'offline', qos: 1, retain: true },
});

let t = 0;
const bruit = (amp) => (Math.random() - 0.5) * 2 * amp;

client.on('connect', () => {
  console.log(`Simulateur ${code} connecté (mode ${mode})`);
  client.publish(`${base}/statut`, 'online', { qos: 1, retain: true });

  setInterval(() => {
    t += 1;
    const derive = mode === 'anomalie' ? Math.min(t / 30, 1) : 0;   // 0 -> 1 en une minute
    const mesure = {
      courant: Number((1.2 + bruit(0.1) + derive * 3.6).toFixed(3)),        // A (seuils 3 / 4.5)
      vibration: Number(Math.max(0, 1 + bruit(1) + derive * 60).toFixed(1)), // imp/s (seuils 20 / 50)
      temperature: Number((27 + bruit(0.3) + derive * 30).toFixed(1)),      // °C (seuils 45 / 60)
      humidite: Number((50 + bruit(1)).toFixed(1)),                         // %
      ts: Date.now(),
      seq: t,
    };
    client.publish(`${base}/mesures`, JSON.stringify(mesure), { qos: 1 });
    console.log(`-> ${base}/mesures`, mesure);
  }, 2000);
});

client.on('error', (e) => { console.error('Erreur MQTT :', e.message); process.exit(1); });
process.on('SIGINT', () => {
  client.publish(`${base}/statut`, 'offline', { qos: 1, retain: true }, () => client.end(false, () => process.exit(0)));
});
