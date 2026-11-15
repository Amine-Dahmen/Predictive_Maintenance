// Démarrage : base de données -> serveur HTTP -> client MQTT -> surveillance des capteurs
const env = require("./config/env");
const app = require("./app");
const { pool } = require("./config/db");
const mqttClient = require("./mqtt/mqtt.client");
const surveillance = require("./services/surveillanceCapteurs.service");
const archivage = require("./services/archivage.service");
const prediction = require("./services/prediction.service");
const logger = require("./utils/logger");

async function start() {
  await pool.query("SELECT 1"); // échoue tout de suite si PostgreSQL est injoignable
  logger.info("PostgreSQL connecté");

  const server = app.listen(env.PORT, "0.0.0.0", () =>
    logger.info(`API démarrée sur http://0.0.0.0:${env.PORT}/api`),
  );

  mqttClient.connect();
  surveillance.start();
  archivage.start(); // US-40
  prediction.start(); // US-22

  const shutdown = async (signal) => {
    logger.info(`${signal} reçu, arrêt propre...`);
    surveillance.stop();
    archivage.stop();
    prediction.stop();
    server.close();
    await mqttClient.disconnect();
    await pool.end();
    process.exit(0);
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

start().catch((err) => {
  logger.error("Impossible de démarrer :", err.message);
  process.exit(1);
});
