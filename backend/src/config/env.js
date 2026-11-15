// Chargement et validation des variables d'environnement.
// Le serveur refuse de démarrer si une variable obligatoire manque ou si un secret est trop faible.
require("dotenv").config();
const { z } = require("zod");

// Variable vide (ex. « PUBLIC_BASE_URL= » ou docker compose) = variable absente
const facultatif = (type) => z.preprocess((v) => (v === "" ? undefined : v), type.optional());

const schema = z.object({
  NODE_ENV: z
    .enum(["development", "production", "test"])
    .default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  CORS_ORIGINS: z.string().default(""),

  DATABASE_URL: z.string().min(1).optional(),
  DB_HOST: z.string().default("localhost"),
  DB_PORT: z.coerce.number().int().positive().default(5432),
  DB_NAME: z.string().default("maintenance_iot"),
  DB_USER: z.string().default("maint"),
  DB_PASSWORD: z.string().min(1).default("maint_password"),

  JWT_ACCESS_SECRET: z
    .string()
    .min(32, "JWT_ACCESS_SECRET doit faire au moins 32 caractères"),
  JWT_REFRESH_SECRET: z
    .string()
    .min(32, "JWT_REFRESH_SECRET doit faire au moins 32 caractères"),
  JWT_ACCESS_EXPIRES_IN: z.string().default("15m"),
  JWT_REFRESH_EXPIRES_DAYS: z.coerce.number().int().positive().default(7),

  MQTT_URL: z.string().default("mqtt://localhost:1883"),
  MQTT_USERNAME: z.string().optional(),
  MQTT_PASSWORD: z.string().optional(),
  MQTT_CLIENT_ID: z.string().default("backend-maintenance"),
  MQTT_TOPIC_PREFIX: z.string().default("usine"),

  CAPTEUR_DELAI_INACTIVITE_S: z.coerce.number().int().positive().default(60),

  // ---------- Release 3 ----------
  // US-38 : e-mails d'alerte (désactivés si SMTP_HOST est vide : les e-mails sont alors seulement journalisés)
  SMTP_HOST: facultatif(z.string()),
  SMTP_PORT: z.coerce.number().int().positive().default(587),
  SMTP_SECURE: z.enum(["true", "false"]).default("false").transform((v) => v === "true"),
  SMTP_USER: z.string().optional(),
  SMTP_PASSWORD: z.string().optional(),
  SMTP_FROM: z.string().default("PrédiMaint <noreply@usine.local>"),
  // US-25 : dossier des photos d'intervention
  UPLOADS_DIR: z.string().default("uploads"),
  // US-40 : les mesures brutes plus anciennes sont résumées par heure puis supprimées (0 = jamais)
  MESURES_RETENTION_JOURS: z.coerce.number().int().min(0).default(90),
  // US-46 : dossier des versions de firmware et adresse de l'API vue par les cartes ESP32
  FIRMWARE_DIR: z.string().default("firmware"),
  PUBLIC_BASE_URL: facultatif(z.string().url()),

  // ---------- US-22 : service d'IA (ml/) ----------
  ML_URL: z.string().url().default("http://localhost:8000"),
  ML_API_KEY: facultatif(z.string()),
  PREDICTION_INTERVALLE_S: z.coerce.number().int().min(0).default(300), // 0 = désactivé
  PREDICTION_PAS_S: z.coerce.number().int().min(10).max(86400).default(3600),

  SEED_DIRECTEUR_EMAIL: z.string().email().default("directeur@usine.local"),
  SEED_DIRECTEUR_PASSWORD: z
    .string()
    .min(12, "SEED_DIRECTEUR_PASSWORD doit faire au moins 12 caractères")
    .default("IhebDeruich123!"),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  console.error("Configuration invalide :");
  for (const issue of parsed.error.issues)
    console.error(` - ${issue.path.join(".")} : ${issue.message}`);
  process.exit(1);
}

const env = parsed.data;
if (env.JWT_ACCESS_SECRET === env.JWT_REFRESH_SECRET) {
  console.error(
    "JWT_ACCESS_SECRET et JWT_REFRESH_SECRET doivent être différents.",
  );
  process.exit(1);
}

env.corsOrigins = env.CORS_ORIGINS.split(",")
  .map((o) => o.trim())
  .filter(Boolean);
env.isProd = env.NODE_ENV === "production";

module.exports = env;
