-- =====================================================================
-- Schéma initial — Application IoT de maintenance prédictive
-- Correspond au diagramme de classes simplifié :
--   Utilisateur (Directeur / Responsable / Technicien), Machine, Capteur,
--   Mesure, Seuil, Alerte, Intervention, CompteRendu, OrdreFabrication
-- =====================================================================

-- ---------- Types énumérés ----------
CREATE TYPE role_utilisateur    AS ENUM ('DIRECTEUR', 'RESPONSABLE', 'TECHNICIEN');
CREATE TYPE statut_compte       AS ENUM ('ACTIF', 'DESACTIVE');
CREATE TYPE etat_machine        AS ENUM ('NORMAL', 'ALERTE', 'PANNE', 'EN_MAINTENANCE', 'SANS_DONNEES');
CREATE TYPE type_mesure         AS ENUM ('COURANT', 'VIBRATION');
CREATE TYPE niveau_alerte       AS ENUM ('ALERTE', 'CRITIQUE');
CREATE TYPE statut_alerte       AS ENUM ('OUVERTE', 'PRISE_EN_COMPTE', 'CLOTUREE');
CREATE TYPE type_intervention   AS ENUM ('PREVENTIVE', 'PREDICTIVE', 'CURATIVE');
CREATE TYPE priorite            AS ENUM ('BASSE', 'MOYENNE', 'HAUTE', 'URGENTE');
CREATE TYPE statut_intervention AS ENUM ('A_AFFECTER', 'AFFECTEE', 'EN_COURS', 'CLOTUREE', 'ANNULEE');
CREATE TYPE statut_of           AS ENUM ('PLANIFIE', 'EN_COURS', 'TERMINE');

-- ---------- Utilisateurs (héritage : une table + colonne role) ----------
CREATE TABLE utilisateurs (
  id                 SERIAL PRIMARY KEY,
  nom                VARCHAR(80)  NOT NULL,
  prenom             VARCHAR(80)  NOT NULL,
  email              VARCHAR(160) NOT NULL UNIQUE,
  telephone          VARCHAR(30),
  mot_de_passe_hash  VARCHAR(100) NOT NULL,
  role               role_utilisateur NOT NULL,
  statut             statut_compte NOT NULL DEFAULT 'ACTIF',
  doit_changer_mdp   BOOLEAN NOT NULL DEFAULT TRUE,
  -- champs propres au technicien
  specialite         VARCHAR(80),
  disponible         BOOLEAN NOT NULL DEFAULT TRUE,
  -- hiérarchie : directeur -> responsables -> techniciens
  cree_par           INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  date_desactivation TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Jetons de rafraîchissement (stockés hachés, révocables)
CREATE TABLE refresh_tokens (
  id             SERIAL PRIMARY KEY,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateurs(id) ON DELETE CASCADE,
  token_hash     CHAR(64) NOT NULL UNIQUE,
  expires_at     TIMESTAMPTZ NOT NULL,
  revoked_at     TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_refresh_user ON refresh_tokens(utilisateur_id);

-- ---------- Parc machines et IoT ----------
CREATE TABLE machines (
  id          SERIAL PRIMARY KEY,
  code        VARCHAR(40)  NOT NULL UNIQUE,
  nom         VARCHAR(120) NOT NULL,
  emplacement VARCHAR(120),
  etat        etat_machine NOT NULL DEFAULT 'SANS_DONNEES',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE capteurs (
  id                SERIAL PRIMARY KEY,
  identifiant       VARCHAR(60) NOT NULL UNIQUE,      -- utilisé dans les topics MQTT
  machine_id        INTEGER NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  type              type_mesure NOT NULL,
  unite             VARCHAR(10) NOT NULL,             -- A ou mm/s
  actif             BOOLEAN NOT NULL DEFAULT TRUE,
  en_ligne          BOOLEAN NOT NULL DEFAULT FALSE,
  derniere_mesure_at TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_capteurs_machine ON capteurs(machine_id);

CREATE TABLE mesures (
  id          BIGSERIAL PRIMARY KEY,
  capteur_id  INTEGER NOT NULL REFERENCES capteurs(id) ON DELETE CASCADE,
  valeur      DOUBLE PRECISION NOT NULL,
  horodatage  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_mesures_capteur_date ON mesures(capteur_id, horodatage DESC);

CREATE TABLE seuils (
  id              SERIAL PRIMARY KEY,
  machine_id      INTEGER NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  type_mesure     type_mesure NOT NULL,
  seuil_alerte    DOUBLE PRECISION NOT NULL CHECK (seuil_alerte > 0),
  seuil_critique  DOUBLE PRECISION NOT NULL,
  modifie_par     INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (machine_id, type_mesure),
  CHECK (seuil_critique > seuil_alerte)
);

CREATE TABLE alertes (
  id                  SERIAL PRIMARY KEY,
  machine_id          INTEGER NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  capteur_id          INTEGER NOT NULL REFERENCES capteurs(id) ON DELETE CASCADE,
  mesure_id           BIGINT REFERENCES mesures(id) ON DELETE SET NULL,
  niveau              niveau_alerte NOT NULL,
  valeur              DOUBLE PRECISION NOT NULL,
  seuil_depasse       DOUBLE PRECISION NOT NULL,
  statut              statut_alerte NOT NULL DEFAULT 'OUVERTE',
  prise_en_compte_par INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  prise_en_compte_at  TIMESTAMPTZ,
  cloturee_at         TIMESTAMPTZ,
  commentaire         TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_alertes_machine ON alertes(machine_id, created_at DESC);
-- Une seule alerte non clôturée à la fois par capteur (évite les doublons)
CREATE UNIQUE INDEX uq_alerte_ouverte_par_capteur ON alertes(capteur_id) WHERE statut <> 'CLOTUREE';

-- ---------- Maintenance ----------
CREATE TABLE interventions (
  id             SERIAL PRIMARY KEY,
  machine_id     INTEGER NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  alerte_id      INTEGER REFERENCES alertes(id) ON DELETE SET NULL,
  type           type_intervention NOT NULL,
  priorite       priorite NOT NULL DEFAULT 'MOYENNE',
  statut         statut_intervention NOT NULL DEFAULT 'A_AFFECTER',
  description    TEXT NOT NULL,
  date_prevue    TIMESTAMPTZ,
  echeance       TIMESTAMPTZ,
  debut_panne    TIMESTAMPTZ,          -- curative : début de la panne (MTBF / MTTR)
  date_debut     TIMESTAMPTZ,
  date_fin       TIMESTAMPTZ,
  resultat       VARCHAR(30),          -- REMISE_EN_SERVICE / NON_RESOLU
  cree_par       INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  technicien_id  INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_interventions_machine ON interventions(machine_id);
CREATE INDEX idx_interventions_technicien ON interventions(technicien_id);

CREATE TABLE comptes_rendus (
  id                SERIAL PRIMARY KEY,
  intervention_id   INTEGER NOT NULL UNIQUE REFERENCES interventions(id) ON DELETE CASCADE,
  diagnostic        TEXT,
  actions           TEXT,
  pieces_utilisees  TEXT,
  brouillon         BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------- Production ----------
CREATE TABLE ordres_fabrication (
  id                  SERIAL PRIMARY KEY,
  numero              VARCHAR(40) NOT NULL UNIQUE,
  machine_id          INTEGER NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  produit             VARCHAR(120) NOT NULL,
  quantite_prevue     INTEGER NOT NULL CHECK (quantite_prevue >= 0),
  quantite_produite   INTEGER NOT NULL DEFAULT 0 CHECK (quantite_produite >= 0),
  quantite_rebutee    INTEGER NOT NULL DEFAULT 0 CHECK (quantite_rebutee >= 0),
  temps_cycle_s       DOUBLE PRECISION,  -- temps de cycle théorique (pour le TRS)
  date_debut          TIMESTAMPTZ,
  date_fin            TIMESTAMPTZ,
  statut              statut_of NOT NULL DEFAULT 'PLANIFIE',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table de suivi des migrations exécutées
CREATE TABLE IF NOT EXISTS schema_migrations (
  nom        VARCHAR(200) PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
