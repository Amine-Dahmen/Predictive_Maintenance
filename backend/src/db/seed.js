// Crée le premier compte Directeur (super administrateur) et des données de démonstration.
// Usage : npm run db:seed
const env = require("../config/env");
const { pool } = require("../config/db");
const { hashPassword } = require("../utils/password");
const logger = require("../utils/logger");
const { TYPES_MESURE, UNITES_PAR_DEFAUT, SEUILS_PAR_DEFAUT } = require("../utils/mesures");

async function seed() {
  const email = env.SEED_DIRECTEUR_EMAIL;
  const password = env.SEED_DIRECTEUR_PASSWORD;
  if (!email || !password)
    throw new Error(
      "Définissez SEED_DIRECTEUR_EMAIL et SEED_DIRECTEUR_PASSWORD dans .env",
    );

  const exists = await pool.query(
    "SELECT id FROM utilisateurs WHERE email = $1",
    [email.toLowerCase()],
  );
  if (exists.rowCount === 0) {
    await pool.query(
      `INSERT INTO utilisateurs (nom, prenom, email, mot_de_passe_hash, role, doit_changer_mdp)
       VALUES ('Directeur', 'Production', $1, $2, 'DIRECTEUR', TRUE)`,
      [email.toLowerCase(), await hashPassword(password)],
    );
    logger.info(
      `Compte directeur créé : ${email} (changement de mot de passe exigé à la 1re connexion)`,
    );
  } else {
    logger.info("Compte directeur déjà présent.");
  }

  // Données de démonstration : la machine M01 équipée de la carte ESP32 PrédiMaint
  // (4 capteurs : courant ACS712, vibration SW-420, température et humidité DHT22) et ses seuils.
  // Les capteurs / seuils déjà présents ne sont pas modifiés.
  const m = await pool.query(
    `INSERT INTO machines (code, nom, emplacement) VALUES ('M01', 'Presse hydraulique 1', 'Atelier A')
     ON CONFLICT (code) DO UPDATE SET code = EXCLUDED.code RETURNING id`,
  );
  const machineId = m.rows[0].id;
  for (const type of TYPES_MESURE) {
    await pool.query(
      `INSERT INTO capteurs (identifiant, machine_id, type, unite) VALUES ($1, $2, $3, $4)
       ON CONFLICT (identifiant) DO NOTHING`,
      [`M01-${type}`, machineId, type, UNITES_PAR_DEFAUT[type]],
    );
    const [alerte, critique] = SEUILS_PAR_DEFAUT[type];
    await pool.query(
      `INSERT INTO seuils (machine_id, type_mesure, seuil_alerte, seuil_critique) VALUES ($1, $2, $3, $4)
       ON CONFLICT (machine_id, type_mesure) DO NOTHING`,
      [machineId, type, alerte, critique],
    );
  }
  logger.info(
    `Données de démonstration prêtes (machine M01, capteurs ${TYPES_MESURE.map((t) => `M01-${t}`).join(", ")}).`,
  );
}

seed()
  .catch((err) => {
    logger.error(err.message);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
