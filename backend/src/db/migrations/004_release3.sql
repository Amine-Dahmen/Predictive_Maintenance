-- Release 3 : stabilisation, pilotage et administration.

-- US-31 : une alerte peut être marquée comme fausse alerte (exclue des indicateurs et de l'entraînement IA)
ALTER TABLE alertes ADD COLUMN IF NOT EXISTS fausse_alerte BOOLEAN NOT NULL DEFAULT FALSE;

-- US-34 : coût d'une heure d'arrêt de production, par machine (en dinars, ou la devise de l'usine)
ALTER TABLE machines ADD COLUMN IF NOT EXISTS cout_horaire_arret NUMERIC(12, 2) NOT NULL DEFAULT 0
  CHECK (cout_horaire_arret >= 0);

-- US-39 : calibration d'un capteur. valeur enregistrée = gain x valeur brute + offset
ALTER TABLE capteurs ADD COLUMN IF NOT EXISTS calibration_gain DOUBLE PRECISION NOT NULL DEFAULT 1
  CHECK (calibration_gain > 0);
ALTER TABLE capteurs ADD COLUMN IF NOT EXISTS calibration_offset DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE capteurs ADD COLUMN IF NOT EXISTS calibre_at TIMESTAMPTZ;
ALTER TABLE capteurs ADD COLUMN IF NOT EXISTS calibre_par INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL;

-- US-37 : remplacement d'un capteur. L'ancien est retiré (actif = FALSE) mais garde son historique.
ALTER TABLE capteurs ADD COLUMN IF NOT EXISTS retire_at TIMESTAMPTZ;
ALTER TABLE capteurs ADD COLUMN IF NOT EXISTS remplace_par INTEGER REFERENCES capteurs(id) ON DELETE SET NULL;

-- US-25 : photos jointes à une intervention (fichiers stockés sur disque, métadonnées en base)
CREATE TABLE IF NOT EXISTS intervention_photos (
  id              SERIAL PRIMARY KEY,
  intervention_id INTEGER NOT NULL REFERENCES interventions(id) ON DELETE CASCADE,
  fichier         VARCHAR(80) NOT NULL UNIQUE,    -- nom généré par le serveur, jamais celui du client
  type_mime       VARCHAR(30) NOT NULL,
  taille          INTEGER NOT NULL,
  legende         VARCHAR(200),
  ajoute_par      INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_photos_intervention ON intervention_photos(intervention_id);

-- US-38 : canaux de notification configurables par l'administrateur (directeur)
CREATE TABLE IF NOT EXISTS canaux_notification (
  canal          VARCHAR(20) PRIMARY KEY,         -- APP (flux temps réel + mobile), EMAIL
  actif          BOOLEAN NOT NULL DEFAULT TRUE,
  niveau_min     niveau_alerte NOT NULL DEFAULT 'ALERTE',
  destinataires  TEXT,                            -- e-mails supplémentaires, séparés par des virgules
  modifie_par    INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO canaux_notification (canal, actif, niveau_min) VALUES
  ('APP', TRUE, 'ALERTE'),
  ('EMAIL', FALSE, 'CRITIQUE')
ON CONFLICT (canal) DO NOTHING;

-- US-40 : archivage. Les mesures brutes anciennes sont résumées par heure puis supprimées.
CREATE TABLE IF NOT EXISTS mesures_horaires (
  capteur_id  INTEGER NOT NULL REFERENCES capteurs(id) ON DELETE CASCADE,
  heure       TIMESTAMPTZ NOT NULL,
  nb          INTEGER NOT NULL,
  moyenne     DOUBLE PRECISION NOT NULL,
  minimum     DOUBLE PRECISION NOT NULL,
  maximum     DOUBLE PRECISION NOT NULL,
  PRIMARY KEY (capteur_id, heure)
);

-- US-46 : suivi des mises à jour du firmware à distance (OTA)
CREATE TABLE IF NOT EXISTS firmware_deploiements (
  id          SERIAL PRIMARY KEY,
  machine_id  INTEGER NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  version     VARCHAR(40) NOT NULL,
  statut      VARCHAR(20) NOT NULL DEFAULT 'ENVOYE',  -- ENVOYE, EN_COURS, REUSSI, ECHEC
  message     TEXT,
  lance_par   INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  -- jeton de téléchargement donné à la carte (haché, comme les refresh tokens), valable 30 minutes
  token_hash  CHAR(64) UNIQUE,
  expire_at   TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_firmware_machine ON firmware_deploiements(machine_id, created_at DESC);
ALTER TABLE machines ADD COLUMN IF NOT EXISTS firmware_version VARCHAR(40);
